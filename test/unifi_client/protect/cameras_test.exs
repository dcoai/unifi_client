defmodule UnifiClient.Protect.CamerasTest do
  use ExUnit.Case, async: true

  doctest UnifiClient.Protect.Cameras

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.Cameras

  @stub __MODULE__.Stub
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, "fake">>

  setup do
    {:ok, udm} = Client.new(host: "unvr.local")
    {:ok, controller} = Client.new(host: "ctl.local", type: :controller)
    %{udm: udm, controller: controller, plug: [plug: {Req.Test, @stub}]}
  end

  defp jpeg(conn) do
    conn
    |> Plug.Conn.put_resp_content_type("image/jpeg")
    |> Plug.Conn.send_resp(200, @jpeg)
  end

  test "list/1 and get/2", %{udm: udm, plug: plug} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.method == "GET"

      case conn.request_path do
        "/proxy/protect/api/cameras" -> Req.Test.json(conn, [%{"id" => "c1"}, %{"id" => "c2"}])
        "/proxy/protect/api/cameras/c2" -> Req.Test.json(conn, %{"id" => "c2", "name" => "Yard"})
      end
    end)

    assert {:ok, [%{"id" => "c1"}, %{"id" => "c2"}]} = Cameras.list(udm, plug)
    assert {:ok, %{"name" => "Yard"}} = Cameras.get(udm, "c2", plug)
  end

  test "update/3 PATCHes the params verbatim", %{udm: udm, plug: plug} do
    Req.Test.stub(@stub, fn conn ->
      assert conn.method == "PATCH"
      assert conn.request_path == "/proxy/protect/api/cameras/c1"
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert Jason.decode!(body) == %{
               "name" => "Porch",
               "recordingSettings" => %{"mode" => "always"}
             }

      Req.Test.json(conn, %{"id" => "c1", "name" => "Porch"})
    end)

    params = %{"name" => "Porch", "recordingSettings" => %{"mode" => "always"}}
    assert {:ok, %{"name" => "Porch"}} = Cameras.update(udm, "c1", params, plug)
  end

  describe "snapshot/3" do
    test "returns the JPEG bytes by default with no query", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/protect/api/cameras/c1/snapshot"
        assert conn.query_string == ""
        jpeg(conn)
      end)

      assert {:ok, @jpeg} = Cameras.snapshot(udm, "c1", plug)
    end

    test "sends only the given query keys, ts as epoch ms", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string) == %{"ts" => "1000", "w" => "640"}
        jpeg(conn)
      end)

      assert {:ok, _} =
               Cameras.snapshot(udm, "c1", [ts: ~U[1970-01-01 00:00:01Z], w: 640] ++ plug)
    end

    @tag :tmp_dir
    test "dest: path writes the file", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "c1.jpg")
      Req.Test.stub(@stub, &jpeg/1)

      assert {:ok, ^dest} = Cameras.snapshot(udm, "c1", [dest: dest] ++ plug)
      assert File.read!(dest) == @jpeg
    end

    @tag :tmp_dir
    test "a Protect error writes nothing", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "nope.jpg")

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{
          "error" => "Camera not found",
          "name" => "NotFound",
          "statusCode" => 404
        })
      end)

      assert {:error, %Error{code: :not_found, message: "Camera not found"}} =
               Cameras.snapshot(udm, "nope", [dest: dest] ++ plug)

      refute File.exists?(dest)
    end
  end

  test "every function is unavailable on a :controller", %{controller: c} do
    assert {:error, %Error{code: :app_unavailable}} = Cameras.list(c)
    assert {:error, %Error{code: :app_unavailable}} = Cameras.get(c, "x")
    assert {:error, %Error{code: :app_unavailable}} = Cameras.update(c, "x", %{})
    assert {:error, %Error{code: :app_unavailable}} = Cameras.snapshot(c, "x")
  end
end
