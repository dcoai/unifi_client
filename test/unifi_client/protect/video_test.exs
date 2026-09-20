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

    test "channel: and fps: are sent only when given", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        q = URI.decode_query(conn.query_string)
        send(self(), {:query, q})
        mp4(conn)
      end)

      assert {:ok, _} = Video.export(udm, "cam1", 0, 1_000, :memory, plug)
      assert_received {:query, q}
      refute Map.has_key?(q, "channel")
      refute Map.has_key?(q, "fps")

      assert {:ok, _} =
               Video.export(
                 udm,
                 "cam1",
                 0,
                 1_000,
                 :memory,
                 [channel: 1, type: :timelapse, fps: 5] ++ plug
               )

      assert_received {:query, %{"channel" => "1", "type" => "timelapse", "fps" => "5"}}
    end
  end

  describe "export_many/6" do
    # Stub that answers per camera id: "missing" → Protect 404, anything else → MP4.
    defp per_camera_stub do
      fn conn ->
        case URI.decode_query(conn.query_string)["camera"] do
          "missing" ->
            conn
            |> Plug.Conn.put_status(404)
            |> Req.Test.json(%{
              "error" => "No recordings",
              "name" => "NotFound",
              "statusCode" => 404
            })

          _ ->
            mp4(conn)
        end
      end
    end

    @tag :tmp_dir
    test "one file per camera, per-camera errors, input order", %{
      udm: udm,
      plug: plug,
      tmp_dir: dir
    } do
      Req.Test.stub(@stub, per_camera_stub())
      out = Path.join(dir, "batch")

      assert {:ok, results} = Video.export_many(udm, ["a", "missing", "b"], 0, 1_000, out, plug)

      assert [
               {"a", {:ok, a_path}},
               {"missing", {:error, %Error{code: :not_found}}},
               {"b", {:ok, b_path}}
             ] = results

      assert a_path == Path.join(out, "a.mp4")
      assert b_path == Path.join(out, "b.mp4")
      assert File.ls!(out) |> Enum.sort() == ["a.mp4", "b.mp4"]
    end

    @tag :tmp_dir
    test "dest: fun overrides the layout; other opts reach export/6", %{
      udm: udm,
      plug: plug,
      tmp_dir: dir
    } do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string)["channel"] == "2"
        mp4(conn)
      end)

      dest = fn id -> Path.join(dir, "cam-#{id}-low.mp4") end

      assert {:ok, [{"x", {:ok, path}}]} =
               Video.export_many(udm, ["x"], 0, 1_000, dir, [dest: dest, channel: 2] ++ plug)

      assert path == Path.join(dir, "cam-x-low.mp4")
      assert File.exists?(path)
    end

    @tag :tmp_dir
    test "max_concurrency bounds the exports in flight", %{udm: udm, plug: plug, tmp_dir: dir} do
      {:ok, gauge} = Agent.start_link(fn -> %{now: 0, peak: 0} end)

      Req.Test.stub(@stub, fn conn ->
        Agent.update(gauge, fn %{now: n, peak: p} -> %{now: n + 1, peak: max(p, n + 1)} end)
        Process.sleep(40)
        Agent.update(gauge, fn s -> %{s | now: s.now - 1} end)
        mp4(conn)
      end)

      ids = ["1", "2", "3", "4"]

      assert {:ok, _} = Video.export_many(udm, ids, 0, 1_000, dir, [max_concurrency: 1] ++ plug)
      assert Agent.get(gauge, & &1.peak) == 1

      Agent.update(gauge, fn _ -> %{now: 0, peak: 0} end)
      assert {:ok, _} = Video.export_many(udm, ids, 0, 1_000, dir, [max_concurrency: 4] ++ plug)
      assert Agent.get(gauge, & &1.peak) == 4
    end

    @tag :tmp_dir
    test "batch-level errors make no request", %{udm: udm, controller: c, tmp_dir: dir} do
      Req.Test.stub(@stub, fn _conn -> flunk("no request expected") end)
      plug = [plug: {Req.Test, @stub}]

      assert {:error, %Error{code: :invalid_window}} =
               Video.export_many(udm, ["a"], 5_000, 1_000, dir, plug)

      assert {:error, %Error{code: :app_unavailable}} =
               Video.export_many(c, ["a"], 0, 1_000, dir, plug)

      # a regular file where the directory should be
      blocked = Path.join(dir, "file")
      File.write!(blocked, "x")

      assert {:error, %Error{code: :dir_error}} =
               Video.export_many(udm, ["a"], 0, 1_000, Path.join(blocked, "sub"), plug)
    end

    @tag :tmp_dir
    test "killing the caller kills every in-flight export (cancel contract)", %{
      udm: udm,
      tmp_dir: dir
    } do
      test = self()

      # Each export blocks inside the stub until released, and reports its pid.
      Req.Test.stub(@stub, fn conn ->
        send(test, {:in_flight, self()})

        receive do
          :release -> mp4(conn)
        end
      end)

      {:ok, caller} =
        Task.start(fn ->
          Video.export_many(udm, ["a", "b", "c"], 0, 1_000, dir,
            max_concurrency: 3,
            plug: {Req.Test, @stub}
          )
        end)

      exports =
        for _ <- 1..3 do
          assert_receive {:in_flight, pid}, 1_000
          Process.monitor(pid)
          pid
        end

      Process.exit(caller, :kill)

      for pid <- exports do
        assert_receive {:DOWN, _, :process, ^pid, _}, 1_000
      end

      refute Enum.any?(exports, &Process.alive?/1)
    end
  end

  describe "Cameras.channels/1" do
    test "returns the channel list or []" do
      chans = [%{"id" => 0, "width" => 3840}, %{"id" => 2, "width" => 640}]
      assert UnifiClient.Protect.Cameras.channels(%{"id" => "c", "channels" => chans}) == chans
      assert UnifiClient.Protect.Cameras.channels(%{"id" => "c"}) == []
    end
  end
end
