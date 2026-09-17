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
end
