defmodule UnifiClient.Protect.EventsTest do
  use ExUnit.Case, async: true

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.Events

  @stub __MODULE__.Stub

  setup do
    {:ok, udm} = Client.new(host: "unvr.local")
    {:ok, controller} = Client.new(host: "ctl.local", type: :controller)
    %{udm: udm, controller: controller, plug: [plug: {Req.Test, @stub}]}
  end

  defp image(conn, type, bytes) do
    conn |> Plug.Conn.put_resp_content_type(type) |> Plug.Conn.send_resp(200, bytes)
  end

  describe "list/2" do
    test "with no options sends no query", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/protect/api/events"
        assert conn.query_string == ""
        Req.Test.json(conn, [%{"id" => "e1", "type" => "motion"}])
      end)

      assert {:ok, [%{"id" => "e1"}]} = Events.list(udm, plug)
    end

    test "encodes the window, joined types and limit", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string) == %{
                 "start" => "1000",
                 "end" => "1789646400000",
                 "types" => "motion,smartDetectZone",
                 "limit" => "50"
               }

        Req.Test.json(conn, [])
      end)

      assert {:ok, []} =
               Events.list(
                 udm,
                 [
                   start: ~U[1970-01-01 00:00:01Z],
                   end: 1_789_646_400_000,
                   types: ["motion", "smartDetectZone"],
                   limit: 50
                 ] ++ plug
               )
    end

    test "omits absent keys and treats an empty types list as absent", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string) == %{"start" => "5"}
        Req.Test.json(conn, [])
      end)

      assert {:ok, []} = Events.list(udm, [start: 5, types: []] ++ plug)
    end
  end

  describe "thumbnail/3 and heatmap/3" do
    test "return the image bytes by default", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        case conn.request_path do
          "/proxy/protect/api/events/e1/thumbnail" -> image(conn, "image/jpeg", "JPEG")
          "/proxy/protect/api/events/e1/heatmap" -> image(conn, "image/png", "PNG")
        end
      end)

      assert {:ok, "JPEG"} = Events.thumbnail(udm, "e1", plug)
      assert {:ok, "PNG"} = Events.heatmap(udm, "e1", plug)
    end

    @tag :tmp_dir
    test "dest: path writes the file", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "e1.jpg")
      Req.Test.stub(@stub, &image(&1, "image/jpeg", "JPEG"))

      assert {:ok, ^dest} = Events.thumbnail(udm, "e1", [dest: dest] ++ plug)
      assert File.read!(dest) == "JPEG"
    end

    @tag :tmp_dir
    test "a Protect error writes nothing", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "gone.png")

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{
          "error" => "Event not found",
          "name" => "NotFound",
          "statusCode" => 404
        })
      end)

      assert {:error, %Error{code: :not_found}} =
               Events.heatmap(udm, "gone", [dest: dest] ++ plug)

      refute File.exists?(dest)
    end
  end

  test "every function is unavailable on a :controller", %{controller: c} do
    assert {:error, %Error{code: :app_unavailable}} = Events.list(c)
    assert {:error, %Error{code: :app_unavailable}} = Events.thumbnail(c, "x")
    assert {:error, %Error{code: :app_unavailable}} = Events.heatmap(c, "x")
  end
end
