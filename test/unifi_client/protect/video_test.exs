defmodule UnifiClient.Protect.VideoTest do
  use ExUnit.Case, async: true

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.Video

  @stub __MODULE__.Stub
  @mp4 <<0, 0, 0, 0x18, "ftypmp42">>

  setup do
    {:ok, udm} = Client.new(host: "unvr.local", timeout: 30_000)
    {:ok, controller} = Client.new(host: "ctl.local", type: :controller)
    %{udm: udm, controller: controller, plug: [plug: {Req.Test, @stub}]}
  end

  defp mp4(conn) do
    conn |> Plug.Conn.put_resp_content_type("video/mp4") |> Plug.Conn.send_resp(200, @mp4)
  end

  describe "export_timeout/4" do
    test "is the client timeout for short clips", %{udm: udm} do
      assert Video.export_timeout(udm, 0, 10_000) == 30_000
    end

    test "scales with clip length", %{udm: udm} do
      assert Video.export_timeout(udm, 0, 60_000) == 120_000

      assert Video.export_timeout(udm, ~U[2026-01-01 00:00:00Z], ~U[2026-01-01 00:10:00Z]) ==
               1_200_000
    end

    test "timeout: overrides", %{udm: udm} do
      assert Video.export_timeout(udm, 0, 60_000, timeout: 5_000) == 5_000
    end
  end

  describe "export/6" do
    @tag :tmp_dir
    test "streams the MP4 to dest with the full query", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "porch.mp4")

      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/proxy/protect/api/video/export"

        assert URI.decode_query(conn.query_string) == %{
                 "camera" => "cam1",
                 "start" => "1000",
                 "end" => "61000",
                 "type" => "rotating",
                 "filename" => "porch.mp4"
               }

        mp4(conn)
      end)

      assert {:ok, ^dest} =
               Video.export(udm, "cam1", ~U[1970-01-01 00:00:01Z], 61_000, dest, plug)

      assert File.read!(dest) == @mp4
    end

    test "type: and filename: override; :memory returns the bytes", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        q = URI.decode_query(conn.query_string)
        assert q["type"] == "timelapse"
        assert q["filename"] == "day.mp4"
        mp4(conn)
      end)

      assert {:ok, @mp4} =
               Video.export(
                 udm,
                 "cam1",
                 0,
                 1_000,
                 :memory,
                 [type: :timelapse, filename: "day.mp4"] ++ plug
               )
    end

    test ":memory defaults the filename", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string)["filename"] == "export.mp4"
        mp4(conn)
      end)

      assert {:ok, _} = Video.export(udm, "cam1", 0, 1_000, :memory, plug)
    end

    # A function adapter sees the fully-built %Req.Request{}, which is the
    # only place the merged receive_timeout is observable.
    defp capturing_adapter(test_pid) do
      fn request ->
        send(test_pid, {:receive_timeout, request.options[:receive_timeout]})

        response =
          Req.Response.new(status: 200, body: @mp4)
          |> Req.Response.put_header("content-type", "video/mp4")

        {request, response}
      end
    end

    test "passes the derived timeout as receive_timeout", %{udm: udm} do
      adapter = [adapter: capturing_adapter(self())]
      assert {:ok, @mp4} = Video.export(udm, "cam1", 0, 60_000, :memory, adapter)
      assert_received {:receive_timeout, 120_000}
    end

    test "an explicit timeout: wins", %{udm: udm} do
      adapter = [adapter: capturing_adapter(self())]

      assert {:ok, @mp4} =
               Video.export(udm, "cam1", 0, 60_000, :memory, [timeout: 7_000] ++ adapter)

      assert_received {:receive_timeout, 7_000}
    end

    @tag :tmp_dir
    test "no footage is an error and writes nothing", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "none.mp4")

      Req.Test.stub(@stub, fn conn ->
        conn
        |> Plug.Conn.put_status(404)
        |> Req.Test.json(%{"error" => "No recordings", "name" => "NotFound", "statusCode" => 404})
      end)

      assert {:error, %Error{code: :not_found, message: "No recordings"}} =
               Video.export(udm, "cam1", 0, 1_000, dest, plug)

      refute File.exists?(dest)
    end

    @tag :tmp_dir
    test "a console timeout is :timeout and leaves no file", %{udm: udm, plug: plug, tmp_dir: dir} do
      dest = Path.join(dir, "slow.mp4")
      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :timeout) end)

      assert {:error, %Error{code: :timeout}} =
               Video.export(udm, "cam1", 0, 1_000, dest, [retry: false] ++ plug)

      refute File.exists?(dest)
    end

    test "an empty or inverted window is rejected before any request", %{udm: udm} do
      assert {:error, %Error{code: :invalid_window}} =
               Video.export(udm, "cam1", 5_000, 5_000, :memory)

      assert {:error, %Error{code: :invalid_window}} =
               Video.export(udm, "cam1", 5_000, 1_000, :memory)
    end

    test "is unavailable on a :controller", %{controller: c} do
      assert {:error, %Error{code: :app_unavailable}} = Video.export(c, "cam1", 0, 1_000, :memory)
    end
  end
end
