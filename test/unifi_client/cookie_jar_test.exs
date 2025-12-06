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

    test "extracts TOKEN cookie" do
      {:ok, jar} = CookieJar.start_link()

      cookies = [
        "SESSION=abc123; Path=/",
        "TOKEN=my-csrf-token; Path=/"
      ]

      CookieJar.put_cookies(jar, cookies)
      assert CookieJar.get_csrf_token(jar) == "my-csrf-token"
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

      cookies = ["TOKEN=abc; Path=/", "SESSION=xyz; Path=/"]
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
end
