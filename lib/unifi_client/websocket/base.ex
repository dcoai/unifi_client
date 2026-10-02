defmodule UnifiClient.WebSocket.Base do
  @moduledoc """
  What the Network and Protect WebSocket clients share.

  `UnifiClient.WebSocket.Client` and `UnifiClient.Protect.WebSocket` differ
  in their URL, their frame decoding and their message tag. Everything else
  is here, as plain functions their `WebSockex` callbacks delegate to:

    * `conn_opts/1` — the upgrade request's `Cookie` header and SSL options,
      read from the client's `UnifiClient.CookieJar` at call time.
    * The subscriber set, `%{pid => monitor_ref | nil}`: every subscriber is
      monitored and dropped on `:DOWN`, and unsubscribing demonitors.
    * `reconnect/4` — the retry policy, rebuilding the connection on each
      attempt so it presents the session the jar holds *now*. A session
      renewed since the socket opened (`UnifiClient.API`'s 401 handling) is
      therefore the one a reconnect uses.

  Not meant to be called directly.
  """

  require Logger

  alias UnifiClient.{Client, CookieJar}

  @reconnect_interval 5_000
  @max_reconnect_attempts 10

  @typedoc "Subscribers and their monitors; `nil` until `monitor_all/1` runs."
  @type subscribers :: %{pid() => reference() | nil}

  @doc """
  `WebSockex` connection options for a client: the jar's cookies as a
  `Cookie` header, and SSL verification following `verify_ssl`.
  """
  @spec conn_opts(Client.t()) :: keyword()
  def conn_opts(%Client{} = client) do
    [
      extra_headers: [{"Cookie", CookieJar.cookie_header(client.cookie_jar)}],
      ssl_options: ssl_options(client)
    ]
  end

  @doc """
  The subscriber set for a socket's first subscriber.

  It is monitored by `monitor_all/1` from `handle_connect/2`: `start_link`
  runs in the caller, and a monitor belongs to the process that made it.
  """
  @spec subscribers(pid()) :: subscribers()
  def subscribers(pid) when is_pid(pid), do: %{pid => nil}

  @doc "Monitors every subscriber not yet monitored. Idempotent."
  @spec monitor_all(subscribers()) :: subscribers()
  def monitor_all(subscribers) do
    Map.new(subscribers, fn
      {pid, nil} -> {pid, Process.monitor(pid)}
      monitored -> monitored
    end)
  end

  @doc "Adds and monitors a subscriber; one already present is left as is."
  @spec subscribe(subscribers(), pid()) :: subscribers()
  def subscribe(subscribers, pid) when is_map_key(subscribers, pid), do: subscribers
  def subscribe(subscribers, pid), do: Map.put(subscribers, pid, Process.monitor(pid))

  @doc "Removes a subscriber and its monitor."
  @spec unsubscribe(subscribers(), pid()) :: subscribers()
  def unsubscribe(subscribers, pid) do
    {ref, subscribers} = Map.pop(subscribers, pid)
    if ref, do: Process.demonitor(ref, [:flush])
    subscribers
  end

  @doc "Removes a subscriber that has gone down."
  @spec down(subscribers(), pid()) :: subscribers()
  def down(subscribers, pid), do: Map.delete(subscribers, pid)

  @doc "Sends `{tag, message}` to every subscriber."
  @spec broadcast(subscribers(), atom(), term()) :: :ok
  def broadcast(subscribers, tag, message) do
    Enum.each(Map.keys(subscribers), &send(&1, {tag, message}))
  end

  @doc """
  The `handle_disconnect/2` result for a client state with
  `reconnect_attempts` and `unifi_client`.

  Below the attempt cap, waits `:interval` ms (default 5 s) and returns
  `{:reconnect, conn, state}` with a connection rebuilt for `url` from the
  jar's current cookies. At the cap, logs and returns `{:ok, state}`: the
  process stays up without reconnecting.
  """
  @spec reconnect(state, String.t(), String.t(), keyword()) ::
          {:reconnect, WebSockex.Conn.t(), state} | {:ok, state}
        when state: %{reconnect_attempts: non_neg_integer(), unifi_client: Client.t()}
  def reconnect(state, url, log_prefix, opts \\ [])

  def reconnect(%{reconnect_attempts: attempts} = state, _url, log_prefix, _opts)
      when attempts >= @max_reconnect_attempts do
    Logger.error("#{log_prefix} Max reconnect attempts reached, giving up")
    {:ok, state}
  end

  def reconnect(
        %{reconnect_attempts: attempts, unifi_client: client} = state,
        url,
        log_prefix,
        opts
      ) do
    interval = Keyword.get(opts, :interval, @reconnect_interval)
    attempt = attempts + 1

    Logger.info("#{log_prefix} Reconnecting to #{url} in #{interval}ms (attempt #{attempt})")
    Process.sleep(interval)

    %WebSockex.Conn{} = conn = WebSockex.Conn.new(url, conn_opts(client))
    {:reconnect, conn, %{state | reconnect_attempts: attempt}}
  end

  defp ssl_options(%Client{verify_ssl: true}), do: []
  defp ssl_options(%Client{verify_ssl: false}), do: [verify: :verify_none]
end
