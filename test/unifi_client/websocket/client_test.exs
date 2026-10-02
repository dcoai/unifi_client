defmodule UnifiClient.WebSocket.ClientTest do
  use ExUnit.Case, async: true

  doctest UnifiClient.WebSocket.Client

  @moduletag :capture_log

  alias UnifiClient.WebSocket.Base
  alias UnifiClient.WebSocket.Client, as: WS

  setup do
    {:ok, client} = UnifiClient.Client.new(host: "udm.local")
    url = WS.build_url(client, "default")

    state = %WS{
      unifi_client: client,
      site: "default",
      url: url,
      subscribers: Base.subscribers(self())
    }

    %{state: state}
  end

  describe "build_url/2" do
    test "a self-hosted controller has no /proxy/network prefix" do
      {:ok, client} = UnifiClient.Client.new(host: "ctl.local", port: 8443, type: :controller)
      assert WS.build_url(client, "s1") == "wss://ctl.local:8443/wss/s/s1/events"
    end
  end

  describe "handle_frame/2" do
    test "a JSON text frame goes to every subscriber as :unifi_event", %{state: state} do
      event = %{"meta" => %{"message" => "events"}, "data" => [%{"key" => "EVT_WU_Connected"}]}

      assert {:ok, ^state} = WS.handle_frame({:text, Jason.encode!(event)}, state)
      assert_received {:unifi_event, ^event}
    end

    test "undecodable text is dropped", %{state: state} do
      assert {:ok, ^state} = WS.handle_frame({:text, "not json"}, state)
      refute_received {:unifi_event, _}
    end

    test "a ping is answered", %{state: state} do
      assert {:reply, :pong, ^state} = WS.handle_frame({:ping, ""}, state)
    end
  end

  describe "subscribers" do
    test "the starting subscriber is monitored on connect", %{state: state} do
      assert %{subscribers: %{} = subs} = state
      assert subs[self()] == nil

      {:ok, state} = WS.handle_connect(:conn, state)
      assert is_reference(state.subscribers[self()])
    end

    test "subscribe, unsubscribe and :DOWN go through the shared set", %{state: state} do
      other = spawn(fn -> :ok end)

      {:ok, state} = WS.handle_cast({:subscribe, other}, state)
      assert Map.has_key?(state.subscribers, other)

      {:ok, state} = WS.handle_cast({:unsubscribe, other}, state)
      refute Map.has_key?(state.subscribers, other)

      {:ok, state} = WS.handle_info({:DOWN, make_ref(), :process, self(), :normal}, state)
      assert state.subscribers == %{}
    end
  end
end
