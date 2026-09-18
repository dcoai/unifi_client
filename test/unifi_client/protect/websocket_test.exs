defmodule UnifiClient.Protect.WebSocketTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias UnifiClient.{Client, Error}
  alias UnifiClient.Protect.WebSocket

  @stub __MODULE__.Stub

  defp packet(type, payload) do
    bytes = Jason.encode!(payload)
    <<type::8, 1::8, 0::8, 0::8, byte_size(bytes)::32-big, bytes::binary>>
  end

  defp message(update_id, data \\ %{"isMotionDetected" => true}) do
    packet(1, %{
      "action" => "update",
      "modelKey" => "camera",
      "id" => "c1",
      "newUpdateId" => update_id
    }) <>
      packet(2, data)
  end

  defp state(client, id \\ "u0"),
    do: %WebSocket{unifi_client: client, last_update_id: id, subscribers: []}

  setup do
    {:ok, client} = Client.new(host: "unvr.local")
    %{client: client}
  end

  describe "handle_binary/2" do
    test "one message in one frame", %{client: c} do
      {events, st} = WebSocket.handle_binary(message("u1"), state(c))
      assert [%{action: %{"newUpdateId" => "u1"}, data: %{"isMotionDetected" => true}}] = events
      assert st.last_update_id == "u1"
      assert st.buffer == <<>>
    end

    test "one message split across two frames", %{client: c} do
      full = message("u1")
      {a, b} = String.split_at(full, 13)

      {[], st} = WebSocket.handle_binary(a, state(c))
      assert st.buffer == a
      assert st.last_update_id == "u0"

      {[%{action: %{"newUpdateId" => "u1"}}], st} = WebSocket.handle_binary(b, st)
      assert st.buffer == <<>>
      assert st.last_update_id == "u1"
    end

    test "two messages coalesced in one frame, plus a partial third", %{client: c} do
      third = message("u3")
      {head, _} = String.split_at(third, 5)
      frame = message("u1") <> message("u2", %{"x" => 1}) <> head

      {events, st} = WebSocket.handle_binary(frame, state(c))
      assert Enum.map(events, & &1.action["newUpdateId"]) == ["u1", "u2"]
      assert st.last_update_id == "u2"
      assert st.buffer == head
    end

    test "an action without newUpdateId keeps the cursor", %{client: c} do
      frame =
        packet(1, %{"action" => "add", "modelKey" => "event", "id" => "e1"}) <> packet(2, %{})

      {[%{action: %{"action" => "add"}}], st} = WebSocket.handle_binary(frame, state(c, "keep"))
      assert st.last_update_id == "keep"
    end

    test "corrupt data drops the buffer and yields nothing", %{client: c} do
      # valid header claiming JSON, garbage payload
      bad = <<1::8, 1::8, 0::8, 0::8, 3::32-big, "{{{">>
      {[], st} = WebSocket.handle_binary(bad, state(c))
      assert st.buffer == <<>>

      # and a good message after a bad one in the same frame is lost with it,
      # which is the documented trade-off
      {[], st} = WebSocket.handle_binary(bad <> message("u9"), state(c))
      assert st.buffer == <<>>
      assert st.last_update_id == "u0"
    end
  end

  describe "build_url/2" do
    test "uses the Protect prefix and the current cursor", %{client: c} do
      assert WebSocket.build_url(c, "abc") ==
               "wss://unvr.local:443/proxy/protect/ws/updates?lastUpdateId=abc"
    end

    test "encodes the cursor", %{client: c} do
      assert WebSocket.build_url(c, "a b&c") =~ "lastUpdateId=a+b%26c"
    end
  end

  describe "start_link/1" do
    test "with last_update_id: given does not call bootstrap", %{client: _} do
      # Port 1 refuses immediately, so the connect fails fast; the stub
      # fails the test if bootstrap is ever requested.
      {:ok, client} = Client.new(host: "127.0.0.1", port: 1)
      Req.Test.stub(@stub, fn _conn -> flunk("bootstrap must not be called") end)

      assert {:error, _connect_error} =
               WebSocket.start_link(
                 client: client,
                 last_update_id: "given",
                 bootstrap_opts: [plug: {Req.Test, @stub}]
               )
    end

    test "bootstraps for the cursor when not given", %{client: _} do
      {:ok, client} = Client.new(host: "127.0.0.1", port: 1)
      test = self()

      Req.Test.stub(@stub, fn conn ->
        send(test, {:bootstrap_path, conn.request_path})
        Req.Test.json(conn, %{"lastUpdateId" => "from-boot", "cameras" => []})
      end)

      assert {:error, _connect_error} =
               WebSocket.start_link(client: client, bootstrap_opts: [plug: {Req.Test, @stub}])

      assert_received {:bootstrap_path, "/proxy/protect/api/bootstrap"}
    end

    test "a bootstrap without a cursor is an error", %{client: _} do
      {:ok, client} = Client.new(host: "127.0.0.1", port: 1)
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"cameras" => []}) end)

      assert {:error, %Error{code: :no_update_id}} =
               WebSocket.start_link(client: client, bootstrap_opts: [plug: {Req.Test, @stub}])
    end

    test "is unavailable on a :controller" do
      {:ok, controller} = Client.new(host: "ctl.local", type: :controller)
      assert {:error, %Error{code: :app_unavailable}} = WebSocket.start_link(client: controller)
    end
  end
end
