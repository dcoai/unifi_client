defmodule UnifiClient.APITest do
  use ExUnit.Case, async: true

  alias UnifiClient.{API, Client, Error}

  @stub UnifiClient.APITest.Stub

  setup do
    {:ok, udm} = Client.new(host: "udm.local")
    {:ok, controller} = Client.new(host: "ctl.local", type: :controller)
    %{udm: udm, controller: controller, plug: [plug: {Req.Test, @stub}]}
  end

  defp protect_error(conn, status, name, msg) do
    conn
    |> Plug.Conn.put_status(status)
    |> Req.Test.json(%{"error" => msg, "name" => name, "statusCode" => status})
  end

  describe "app: option" do
    test "defaults to the Network prefix", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/network/api/self"
        Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"name" => "admin"}]})
      end)

      assert {:ok, [%{"name" => "admin"}]} = API.get(udm, "/api/self", plug)
    end

    test "app: :protect uses the Protect prefix", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/protect/api/bootstrap"
        Req.Test.json(conn, %{"lastUpdateId" => "abc", "cameras" => []})
      end)

      assert {:ok, %{"lastUpdateId" => "abc"}} =
               API.get(udm, "/api/bootstrap", [app: :protect] ++ plug)
    end

    test "does not double-prefix a path that already carries the app prefix", %{
      udm: udm,
      plug: plug
    } do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/protect/api/cameras"
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = API.get(udm, "/proxy/protect/api/cameras", [app: :protect] ++ plug)
    end

    test "a Network path is not mistaken for a Protect prefix", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/protect/proxy/network/api/self"
        Req.Test.json(conn, %{})
      end)

      assert {:ok, %{}} = API.get(udm, "/proxy/network/api/self", [app: :protect] ++ plug)
    end

    test ":protect on a :controller client fails before any request", %{
      controller: controller
    } do
      # No stub installed: a request would raise from Req.Test.
      assert {:error, %Error{code: :app_unavailable, reason: :protect}} =
               API.get(controller, "/api/bootstrap", app: :protect, plug: {Req.Test, @stub})

      assert {:error, %Error{code: :app_unavailable}} =
               API.download(controller, "/x", :memory, app: :protect, plug: {Req.Test, @stub})
    end

    test "the app option is not forwarded to Req", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{}) end)
      assert {:ok, %{}} = API.get(udm, "/api/x", [app: :network] ++ plug)
    end
  end

  describe "patch/4" do
    test "sends PATCH with a JSON body", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "PATCH"
        assert conn.request_path == "/proxy/protect/api/cameras/cam1"
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"name" => "Porch"}
        Req.Test.json(conn, %{"id" => "cam1", "name" => "Porch"})
      end)

      assert {:ok, %{"name" => "Porch"}} =
               API.patch(udm, "/api/cameras/cam1", %{"name" => "Porch"}, [app: :protect] ++ plug)
    end
  end

  describe "Protect error bodies" do
    test "are errors even on a 200", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn -> protect_error(conn, 200, "Weird", "still an error") end)

      assert {:error, %Error{message: "still an error"}} =
               API.get(udm, "/api/x", [app: :protect] ++ plug)
    end

    test "carry the message and status", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn -> protect_error(conn, 404, "NotFound", "Camera not found") end)

      assert {:error, %Error{code: :not_found, message: "Camera not found", reason: reason}} =
               API.get(udm, "/api/cameras/nope", [app: :protect] ++ plug)

      assert reason == %{status: 404, name: "NotFound"}
    end
  end

  describe "download/4" do
    @tag :tmp_dir
    test "writes a 200 body to dest", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "snap.jpg")

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/jpeg")
        |> Plug.Conn.send_resp(200, <<0xFF, 0xD8, 0xFF, 0xE0, "chunk">>)
      end)

      assert {:ok, ^dest} =
               API.download(udm, "/api/cameras/c/snapshot", dest, [app: :protect] ++ plug)

      assert File.read!(dest) == <<0xFF, 0xD8, 0xFF, 0xE0, "chunk">>
    end

    test "dest: :memory returns the body", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("video/mp4")
        |> Plug.Conn.send_resp(200, "mp4bytes")
      end)

      assert {:ok, "mp4bytes"} =
               API.download(udm, "/api/video/export", :memory, [app: :protect] ++ plug)
    end

    @tag :tmp_dir
    test "a non-200 response is an error and writes nothing", %{
      udm: udm,
      plug: plug,
      tmp_dir: dir
    } do
      dest = Path.join(dir, "never.mp4")

      Req.Test.stub(@stub, fn conn -> protect_error(conn, 404, "NotFound", "No footage") end)

      assert {:error, %Error{code: :not_found, message: "No footage"}} =
               API.download(udm, "/api/video/export", dest, [app: :protect] ++ plug)

      refute File.exists?(dest)
    end

    @tag :tmp_dir
    test "a 401 is an authentication error and writes nothing", %{
      udm: udm,
      plug: plug,
      tmp_dir: dir
    } do
      dest = Path.join(dir, "never.jpg")

      Req.Test.stub(@stub, fn conn ->
        conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "Unauthorized"})
      end)

      assert {:error, %Error{code: :authentication_failed}} =
               API.download(udm, "/api/x", dest, [app: :protect] ++ plug)

      refute File.exists?(dest)
    end

    @tag :tmp_dir
    test "a transport failure removes a partial file", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "partial.mp4")
      File.write!(dest, "stale")

      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, %Error{code: :timeout}} =
               API.download(udm, "/api/video/export", dest, [app: :protect, retry: false] ++ plug)

      refute File.exists?(dest)
    end
  end

  describe "session renewal" do
    # A stub whose behaviour depends on how many times each path was hit.
    # `script` maps {path, nth_call} -> response fun; unknown → flunk.
    defp scripted(script, test_pid) do
      {:ok, counter} = Agent.start_link(fn -> %{} end)

      fn conn ->
        n =
          Agent.get_and_update(counter, fn m ->
            {Map.get(m, conn.request_path, 0) + 1, Map.update(m, conn.request_path, 1, &(&1 + 1))}
          end)

        send(test_pid, {:hit, conn.request_path, n, Plug.Conn.get_req_header(conn, "cookie")})

        case Map.fetch(script, {conn.request_path, n}) do
          {:ok, fun} -> fun.(conn)
          :error -> flunk("unexpected call ##{n} to #{conn.request_path}")
        end
      end
    end

    defp unauthorized(conn),
      do: conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "expired"})

    defp ok_data(conn),
      do: Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"ok" => true}]})

    defp login_ok(conn) do
      conn
      |> Plug.Conn.put_resp_header("set-cookie", "TOKEN=renewed; Path=/; HttpOnly")
      |> Plug.Conn.put_resp_header("x-csrf-token", "csrf2")
      |> Req.Test.json(%{"unique_id" => "u"})
    end

    # The renewal login is built from the client's own Req, so the stub has
    # to be on the client (req_options:), not on the call.
    defp logged_in_client(opts \\ []) do
      {:ok, c} =
        Client.new(
          [
            host: "udm.local",
            username: "svc",
            password: "pw",
            req_options: [plug: {Req.Test, @stub}]
          ] ++
            opts
        )

      Client.mark_logged_in(c)
    end

    test "a 401 triggers one login and the retry carries the new cookie" do
      client = logged_in_client()

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/proxy/network/api/x", 1} => &unauthorized/1,
            {"/api/auth/login", 1} => &login_ok/1,
            {"/proxy/network/api/x", 2} => &ok_data/1
          },
          self()
        )
      )

      assert {:ok, [%{"ok" => true}]} = API.get(client, "/api/x")

      assert_received {:hit, "/proxy/network/api/x", 1, _}
      assert_received {:hit, "/api/auth/login", 1, _}
      assert_received {:hit, "/proxy/network/api/x", 2, ["TOKEN=renewed"]}
      refute_received {:hit, "/api/auth/login", 2, _}
    end

    test "a second 401 after renewal is the auth error; login is hit once" do
      client = logged_in_client()

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/proxy/network/api/x", 1} => &unauthorized/1,
            {"/api/auth/login", 1} => &login_ok/1,
            {"/proxy/network/api/x", 2} => &unauthorized/1
          },
          self()
        )
      )

      assert {:error, %Error{code: :authentication_failed}} = API.get(client, "/api/x")

      refute_received {:hit, "/api/auth/login", 2, _}
      refute_received {:hit, "/proxy/network/api/x", 3, _}
    end

    test "a failed login is returned and the request is not retried" do
      client = logged_in_client()

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/proxy/network/api/x", 1} => &unauthorized/1,
            {"/api/auth/login", 1} => fn conn ->
              conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"errors" => ["bad password"]})
            end
          },
          self()
        )
      )

      assert {:error, %Error{code: :authentication_failed, message: "bad password"}} =
               API.get(client, "/api/x")

      refute_received {:hit, "/proxy/network/api/x", 2, _}
    end

    test "no renewal when opted out, not logged in, or without credentials" do
      test = self()

      Req.Test.stub(@stub, fn conn ->
        send(test, {:hit, conn.request_path, 1, []})
        if conn.request_path =~ "login", do: flunk("login must not be attempted")
        unauthorized(conn)
      end)

      plug = [plug: {Req.Test, @stub}]

      assert {:error, %Error{code: :authentication_failed}} =
               API.get(logged_in_client(), "/api/x", reauth: false)

      {:ok, never_logged_in} = Client.new(host: "udm.local", username: "svc", password: "pw")

      assert {:error, %Error{code: :authentication_failed}} =
               API.get(never_logged_in, "/api/x", plug)

      {:ok, no_pw} = Client.new(host: "udm.local", username: "svc")

      assert {:error, %Error{code: :authentication_failed}} =
               API.get(Client.mark_logged_in(no_pw), "/api/x", plug)

      refute_received {:hit, "/api/auth/login", _, _}
    end

    @tag :tmp_dir
    test "download/4 renews and then writes the file", %{tmp_dir: dir} do
      client = logged_in_client()
      dest = Path.join(dir, "after.jpg")

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/proxy/protect/api/cameras/c/snapshot", 1} => &unauthorized/1,
            {"/api/auth/login", 1} => &login_ok/1,
            {"/proxy/protect/api/cameras/c/snapshot", 2} => fn conn ->
              conn
              |> Plug.Conn.put_resp_content_type("image/jpeg")
              |> Plug.Conn.send_resp(200, "JPEG")
            end
          },
          self()
        )
      )

      assert {:ok, ^dest} =
               API.download(client, "/api/cameras/c/snapshot", dest,
                 app: :protect,
                 plug: {Req.Test, @stub}
               )

      assert File.read!(dest) == "JPEG"
    end

    @tag :tmp_dir
    test "download/4 with 401 twice writes nothing", %{tmp_dir: dir} do
      client = logged_in_client()
      dest = Path.join(dir, "never.jpg")

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/proxy/protect/api/cameras/c/snapshot", 1} => &unauthorized/1,
            {"/api/auth/login", 1} => &login_ok/1,
            {"/proxy/protect/api/cameras/c/snapshot", 2} => &unauthorized/1
          },
          self()
        )
      )

      assert {:error, %Error{code: :authentication_failed}} =
               API.download(client, "/api/cameras/c/snapshot", dest,
                 app: :protect,
                 plug: {Req.Test, @stub}
               )

      refute File.exists?(dest)
    end

    test "a :controller renews through /api/login" do
      client = logged_in_client(type: :controller)

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/api/x", 1} => &unauthorized/1,
            {"/api/login", 1} => &login_ok/1,
            {"/api/x", 2} => &ok_data/1
          },
          self()
        )
      )

      assert {:ok, _} = API.get(client, "/api/x")
      assert_received {:hit, "/api/login", 1, _}
    end
  end

  describe "single-flight renewal and rate limiting" do
    defp counting_stub(test_pid, on_get) do
      {:ok, counter} = Agent.start_link(fn -> %{} end)

      fn conn ->
        n =
          Agent.get_and_update(counter, fn m ->
            {Map.get(m, conn.request_path, 0) + 1, Map.update(m, conn.request_path, 1, &(&1 + 1))}
          end)

        send(test_pid, {:hit, conn.request_path, n})

        case conn.request_path do
          "/api/auth/login" ->
            # slow enough that the other five requests are already waiting
            Process.sleep(50)

            conn
            |> Plug.Conn.put_resp_header("set-cookie", "TOKEN=renewed; Path=/")
            |> Req.Test.json(%{"unique_id" => "u"})

          _ ->
            on_get.(conn, n)
        end
      end
    end

    test "six concurrent requests on an expired session log in exactly once" do
      client = logged_in_client()
      test = self()

      Req.Test.stub(
        @stub,
        counting_stub(test, fn conn, _n ->
          # expired until the renewed cookie arrives
          case Plug.Conn.get_req_header(conn, "cookie") do
            ["TOKEN=renewed"] ->
              Req.Test.json(conn, %{"meta" => %{"rc" => "ok"}, "data" => [%{"ok" => true}]})

            _ ->
              conn |> Plug.Conn.put_status(401) |> Req.Test.json(%{"error" => "expired"})
          end
        end)
      )

      results =
        1..6
        |> Task.async_stream(fn _ -> API.get(client, "/api/x") end, max_concurrency: 6)
        |> Enum.map(fn {:ok, r} -> r end)

      assert Enum.all?(results, &match?({:ok, [%{"ok" => true}]}, &1)), inspect(results)
      assert_received {:hit, "/api/auth/login", 1}
      refute_received {:hit, "/api/auth/login", 2}
    end

    test "a 429 is :rate_limited with retry_after from the header" do
      # retry: false — Req's default retries a GET 429 and honours Retry-After.
      {:ok, client} =
        Client.new(host: "udm.local", req_options: [plug: {Req.Test, @stub}, retry: false])

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(429)
        |> Plug.Conn.put_resp_header("retry-after", "30")
        |> Req.Test.json(%{
          "code" => "AUTHENTICATION_FAILED_LIMIT_REACHED",
          "message" => "You've reached the login attempt limit"
        })
      end)

      assert {:error,
              %Error{
                code: :rate_limited,
                message: "You've reached the login attempt limit",
                reason: reason
              }} =
               API.get(client, "/api/x")

      assert reason.retry_after == 30
      assert reason.status == 429
    end

    test "the UniFi OS limit body is :rate_limited even without a 429 status" do
      {:ok, client} = Client.new(host: "udm.local", req_options: [plug: {Req.Test, @stub}])

      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(conn, %{"code" => "AUTHENTICATION_FAILED_LIMIT_REACHED"})
      end)

      assert {:error, %Error{code: :rate_limited, reason: %{retry_after: nil}}} =
               API.get(client, "/api/x")
    end

    test "a rate-limited login during renewal is returned and not retried" do
      client = logged_in_client()
      test = self()

      Req.Test.stub(
        @stub,
        scripted(
          %{
            {"/proxy/network/api/x", 1} => &unauthorized/1,
            {"/api/auth/login", 1} => fn conn ->
              conn
              |> Plug.Conn.put_status(429)
              |> Req.Test.json(%{"code" => "AUTHENTICATION_FAILED_LIMIT_REACHED"})
            end
          },
          test
        )
      )

      assert {:error, %Error{code: :rate_limited}} = API.get(client, "/api/x")
      refute_received {:hit, "/proxy/network/api/x", 2, _}
    end
  end
end
