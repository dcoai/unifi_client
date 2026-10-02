defmodule UnifiClient.WebSocket.BaseTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias UnifiClient.{Client, CookieJar}
  alias UnifiClient.WebSocket.Base

  defp subscriber do
    spawn(fn ->
      receive do
        :exit -> :ok
      end
    end)
  end

  defp monitored?(pid) do
    {:monitored_by, by} = Process.info(pid, :monitored_by)
    Enum.count(by, &(&1 == self()))
  end

  describe "subscribers" do
    test "the first subscriber is monitored once monitor_all/1 runs" do
      pid = subscriber()
      subs = Base.subscribers(pid)
      assert subs == %{pid => nil}
      assert monitored?(pid) == 0

      subs = Base.monitor_all(subs)
      assert %{^pid => ref} = subs
      assert is_reference(ref)
      assert monitored?(pid) == 1

      assert Base.monitor_all(subs) == subs
      assert monitored?(pid) == 1
    end

    test "subscribing twice monitors once" do
      pid = subscriber()
      subs = %{} |> Base.subscribe(pid) |> Base.subscribe(pid)
      assert Map.keys(subs) == [pid]
      assert monitored?(pid) == 1
    end

    test "unsubscribing removes the monitor" do
      pid = subscriber()
      subs = %{} |> Base.subscribe(pid) |> Base.unsubscribe(pid)
      assert subs == %{}
      assert monitored?(pid) == 0
    end

    test "unsubscribing an unknown or unmonitored pid is harmless" do
      pid = subscriber()
      assert Base.unsubscribe(%{}, pid) == %{}
      assert Base.unsubscribe(Base.subscribers(pid), pid) == %{}
    end

    test "a subscriber that dies is reported and dropped" do
      pid = subscriber()
      subs = Base.subscribe(%{}, pid)
      send(pid, :exit)

      assert_receive {:DOWN, _ref, :process, ^pid, _}
      assert Base.down(subs, pid) == %{}
    end

    test "broadcast sends the tagged message to every subscriber" do
      subs = %{} |> Base.subscribe(self()) |> Map.put(subscriber(), nil)
      assert :ok = Base.broadcast(subs, :tag, %{"x" => 1})
      assert_received {:tag, %{"x" => 1}}
    end
  end

  describe "conn_opts/1" do
    test "reads the jar at call time, so a renewed session is the one sent" do
      {:ok, client} = Client.new(host: "udm.local", verify_ssl: false)
      :ok = CookieJar.put_cookies(client.cookie_jar, ["TOKEN=old; Path=/; HttpOnly"])
      assert [{"Cookie", "TOKEN=old"}] = Base.conn_opts(client)[:extra_headers]

      :ok = CookieJar.put_cookies(client.cookie_jar, ["TOKEN=renewed; Path=/; HttpOnly"])
      assert [{"Cookie", "TOKEN=renewed"}] = Base.conn_opts(client)[:extra_headers]
      assert Base.conn_opts(client)[:ssl_options] == [verify: :verify_none]
    end

    test "SSL verification follows verify_ssl" do
      {:ok, client} = Client.new(host: "udm.local", verify_ssl: true)
      assert Base.conn_opts(client)[:ssl_options] == []
    end
  end

  describe "reconnect/4" do
    setup do
      {:ok, client} = Client.new(host: "udm.local")
      :ok = CookieJar.put_cookies(client.cookie_jar, ["TOKEN=old; Path=/"])
      %{state: %{unifi_client: client, reconnect_attempts: 0}}
    end

    test "rebuilds the connection with the jar's current session", %{state: state} do
      :ok = CookieJar.put_cookies(state.unifi_client.cookie_jar, ["TOKEN=renewed; Path=/"])
      url = "wss://udm.local:443/proxy/network/wss/s/default/events"

      assert {:reconnect, %WebSockex.Conn{} = conn, %{reconnect_attempts: 1}} =
               Base.reconnect(state, url, "[t]", interval: 0)

      assert conn.host == "udm.local"
      assert conn.path == "/proxy/network/wss/s/default/events"
      assert {"Cookie", "TOKEN=renewed"} in conn.extra_headers
    end

    test "gives up at the tenth attempt and stays up", %{state: state} do
      state = %{state | reconnect_attempts: 9}

      assert {:reconnect, _, %{reconnect_attempts: 10} = state} =
               Base.reconnect(state, "wss://udm.local/x", "[t]", interval: 0)

      assert {:ok, ^state} = Base.reconnect(state, "wss://udm.local/x", "[t]", interval: 0)
    end
  end
end
