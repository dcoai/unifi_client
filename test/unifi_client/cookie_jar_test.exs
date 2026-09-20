defmodule UnifiClient.CookieJarTest do
  use ExUnit.Case, async: true

  alias UnifiClient.CookieJar

  describe "start_link/1" do
    test "starts a cookie jar agent" do
      {:ok, jar} = CookieJar.start_link()
      assert is_pid(jar)
    end
  end

  describe "get_cookies/1 and put_cookies/2" do
    test "stores and retrieves cookies" do
      {:ok, jar} = CookieJar.start_link()

      assert CookieJar.get_cookies(jar) == []

      cookies = [
        "SESSION=abc123; Path=/; HttpOnly",
        "CSRF=xyz789; Path=/"
      ]

      CookieJar.put_cookies(jar, cookies)
      assert CookieJar.get_cookies(jar) == cookies
    end
  end

  describe "get_csrf_token/1" do
    test "returns nil when no CSRF token" do
      {:ok, jar} = CookieJar.start_link()
      assert CookieJar.get_csrf_token(jar) == nil
    end

    # UniFi OS: TOKEN is a JWT; the token is its csrfToken claim.
    defp jwt(claims) do
      header = Base.url_encode64(~s({"alg":"HS256","typ":"JWT"}), padding: false)
      payload = Base.url_encode64(Jason.encode!(claims), padding: false)
      "#{header}.#{payload}.signature"
    end

    test "extracts the csrfToken claim from a TOKEN JWT cookie" do
      {:ok, jar} = CookieJar.start_link()

      cookies = [
        "SESSION=abc123; Path=/",
        "TOKEN=#{jwt(%{"csrfToken" => "my-csrf-token", "userId" => "u"})}; Path=/; HttpOnly"
      ]

      CookieJar.put_cookies(jar, cookies)
      assert CookieJar.get_csrf_token(jar) == "my-csrf-token"
    end

    test "a TOKEN cookie that is not a JWT with the claim yields no token" do
      {:ok, jar} = CookieJar.start_link()
      CookieJar.put_csrf_token(jar, "kept")

      for value <- ["opaque", "a.b", "a.!!!.c", "#{jwt(%{"other" => 1})}"] do
        CookieJar.put_cookies(jar, ["TOKEN=#{value}; Path=/"])
        assert CookieJar.get_csrf_token(jar) == "kept", value
      end
    end

    test "the x-csrf-token header overrides a cookie-derived token" do
      {:ok, jar} = CookieJar.start_link()
      CookieJar.put_cookies(jar, ["csrf_token=from-cookie; Path=/"])
      CookieJar.put_csrf_token(jar, "from-header")
      assert CookieJar.get_csrf_token(jar) == "from-header"
    end

    test "extracts csrf_token cookie" do
      {:ok, jar} = CookieJar.start_link()

      cookies = [
        "csrf_token=another-token; Path=/; HttpOnly"
      ]

      CookieJar.put_cookies(jar, cookies)
      assert CookieJar.get_csrf_token(jar) == "another-token"
    end
  end

  describe "clear/1" do
    test "clears all cookies and token" do
      {:ok, jar} = CookieJar.start_link()

      cookies = ["csrf_token=abc; Path=/", "SESSION=xyz; Path=/"]
      CookieJar.put_cookies(jar, cookies)

      assert CookieJar.get_cookies(jar) != []
      assert CookieJar.get_csrf_token(jar) != nil

      CookieJar.clear(jar)

      assert CookieJar.get_cookies(jar) == []
      assert CookieJar.get_csrf_token(jar) == nil
    end
  end

  describe "attach/2" do
    test "attaches request and response steps" do
      {:ok, jar} = CookieJar.start_link()
      req = Req.new()

      attached = CookieJar.attach(req, jar)

      # Check that steps were added
      assert Keyword.has_key?(attached.request_steps, :unifi_add_cookies)
      assert Keyword.has_key?(attached.response_steps, :unifi_save_cookies)
    end
  end

  describe "renew/3 (single-flight)" do
    @moduletag :capture_log

    defp counting_login(counter, result_fun) do
      fn ->
        Agent.update(counter, &(&1 + 1))
        # Make the window in which others can pile up wide enough to matter.
        Process.sleep(50)
        result_fun.()
      end
    end

    test "six concurrent callers produce exactly one login" do
      {:ok, jar} = CookieJar.start_link()
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      login = counting_login(counter, fn -> {:ok, :session} end)

      results =
        1..6
        |> Task.async_stream(fn _ -> CookieJar.renew(jar, 0, login) end, max_concurrency: 6)
        |> Enum.map(fn {:ok, r} -> r end)

      # One login; everyone who waited for it is told :renewed, anyone who
      # arrived after it completed is told :already_renewed.
      assert Agent.get(counter, & &1) == 1
      assert Enum.all?(results, &(&1 in [{:ok, :renewed}, {:ok, :already_renewed}]))
      assert CookieJar.generation(jar) == 1
    end

    test "a caller that saw the current generation does not log in again" do
      {:ok, jar} = CookieJar.start_link()
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      login = counting_login(counter, fn -> {:ok, :session} end)

      assert {:ok, :renewed} = CookieJar.renew(jar, 0, login)
      assert {:ok, :already_renewed} = CookieJar.renew(jar, 0, login)
      assert {:ok, :renewed} = CookieJar.renew(jar, 1, login)
      assert Agent.get(counter, & &1) == 2
      assert CookieJar.generation(jar) == 2
    end

    test "a login failure reaches the owner and every waiter; generation unchanged" do
      {:ok, jar} = CookieJar.start_link()
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      login = counting_login(counter, fn -> {:error, :bad_password} end)

      results =
        1..4
        |> Task.async_stream(fn _ -> CookieJar.renew(jar, 0, login) end, max_concurrency: 4)
        |> Enum.map(fn {:ok, r} -> r end)

      assert results == List.duplicate({:error, :bad_password}, 4)
      assert Agent.get(counter, & &1) == 1
      assert CookieJar.generation(jar) == 0

      # and the lock is released: a later caller logs in again
      assert {:error, :bad_password} = CookieJar.renew(jar, 0, login)
      assert Agent.get(counter, & &1) == 2
    end

    test "an owner that dies mid-login hands the lock to a waiter" do
      {:ok, jar} = CookieJar.start_link()
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      test = self()

      # First caller: takes the lock, then is killed while "logging in".
      owner =
        spawn(fn ->
          CookieJar.renew(jar, 0, fn ->
            send(test, :owner_inside_login)
            Process.sleep(:infinity)
          end)
        end)

      assert_receive :owner_inside_login

      waiter =
        Task.async(fn ->
          CookieJar.renew(jar, 0, counting_login(counter, fn -> {:ok, :session} end))
        end)

      # Give the waiter time to register, then kill the owner.
      Process.sleep(30)
      Process.exit(owner, :kill)

      assert {:ok, :renewed} = Task.await(waiter, 1_000)
      assert Agent.get(counter, & &1) == 1
      assert CookieJar.generation(jar) == 1
    end
  end
end
