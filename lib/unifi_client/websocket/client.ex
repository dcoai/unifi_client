defmodule UnifiClient.WebSocket.Client do
  @moduledoc """
  WebSocket client for real-time UniFi events.

  Connects to the UniFi controller's WebSocket endpoint to receive
  live updates about device status, client connections, and other events.

  ## Usage

  The WebSocket client is implemented as a GenServer that can be started
  and supervised. It sends events to registered subscribers.

      # Start the WebSocket client
      {:ok, ws} = UnifiClient.WebSocket.Client.start_link(
        client: unifi_client,
        site: "default",
        subscriber: self()
      )

      # Handle events in your GenServer
      def handle_info({:unifi_event, event}, state) do
        IO.inspect(event, label: "UniFi Event")
        {:noreply, state}
      end

  ## Event Format

  Events are maps with the following structure:

      %{
        "meta" => %{
          "message" => "events",
          "rc" => "ok"
        },
        "data" => [
          %{
            "key" => "EVT_WU_Connected",
            "msg" => "User[aa:bb:cc:dd:ee:ff] has connected...",
            "time" => 1234567890000,
            ...
          }
        ]
      }

  Common event types:
  - `sta:sync` - Client connected/updated
  - `device:sync` - Device status changed
  - `EVT_WU_Connected` - Wireless user connected
  - `EVT_WU_Disconnected` - Wireless user disconnected
  - `EVT_LU_Connected` - LAN user connected
  - `EVT_AP_Restarted` - Access point restarted

  """

  use WebSockex

  require Logger

  @reconnect_interval 5_000
  @max_reconnect_attempts 10

  defstruct [
    :unifi_client,
    :site,
    :url,
    :subscribers,
    :reconnect_attempts
  ]

  @type t :: %__MODULE__{
          unifi_client: UnifiClient.Client.t(),
          site: String.t(),
          url: String.t(),
          subscribers: [pid()],
          reconnect_attempts: non_neg_integer()
        }

  @doc """
  Starts the WebSocket client.

  ## Options

    * `:client` - Required. The authenticated UnifiClient.Client
    * `:site` - Required. The site name (e.g., "default")
    * `:subscriber` - Optional. PID to receive events (defaults to caller)
    * `:name` - Optional. GenServer name for registration

  ## Returns

    * `{:ok, pid}` - Successfully started
    * `{:error, reason}` - Failed to start

  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    unifi_client = Keyword.fetch!(opts, :client)
    site = Keyword.fetch!(opts, :site)
    subscriber = Keyword.get(opts, :subscriber, self())
    name = Keyword.get(opts, :name)

    url = build_websocket_url(unifi_client, site)
    cookies = get_cookies(unifi_client)

    state = %__MODULE__{
      unifi_client: unifi_client,
      site: site,
      url: url,
      subscribers: [subscriber],
      reconnect_attempts: 0
    }

    ws_opts = [
      extra_headers: [
        {"Cookie", cookies}
      ],
      ssl_options: ssl_options(unifi_client)
    ]

    ws_opts =
      if name do
        Keyword.put(ws_opts, :name, name)
      else
        ws_opts
      end

    WebSockex.start_link(url, __MODULE__, state, ws_opts)
  end

  @doc """
  Subscribes a process to receive events.

  Events are sent as `{:unifi_event, event}` messages.
  """
  @spec subscribe(pid(), pid()) :: :ok
  def subscribe(ws, subscriber) do
    WebSockex.cast(ws, {:subscribe, subscriber})
  end

  @doc """
  Unsubscribes a process from events.
  """
  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(ws, subscriber) do
    WebSockex.cast(ws, {:unsubscribe, subscriber})
  end

  @doc """
  Stops the WebSocket client.
  """
  @spec stop(pid()) :: :ok
  def stop(ws) do
    WebSockex.cast(ws, :stop)
  end

  # WebSockex Callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("[UnifiClient.WebSocket] Connected to #{state.url}")
    {:ok, %{state | reconnect_attempts: 0}}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} ->
        broadcast_event(state.subscribers, event)
        {:ok, state}

      {:error, _} ->
        Logger.warning("[UnifiClient.WebSocket] Failed to decode message: #{inspect(msg)}")
        {:ok, state}
    end
  end

  def handle_frame({:ping, _}, state) do
    {:reply, :pong, state}
  end

  def handle_frame(frame, state) do
    Logger.debug("[UnifiClient.WebSocket] Received frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    subscribers = Enum.uniq([pid | state.subscribers])
    {:ok, %{state | subscribers: subscribers}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    subscribers = List.delete(state.subscribers, pid)
    {:ok, %{state | subscribers: subscribers}}
  end

  def handle_cast(:stop, state) do
    {:close, state}
  end

  @impl WebSockex
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    subscribers = List.delete(state.subscribers, pid)
    {:ok, %{state | subscribers: subscribers}}
  end

  def handle_info(msg, state) do
    Logger.debug("[UnifiClient.WebSocket] Received info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("[UnifiClient.WebSocket] Disconnected: #{inspect(reason)}")

    if state.reconnect_attempts < @max_reconnect_attempts do
      Logger.info(
        "[UnifiClient.WebSocket] Reconnecting in #{@reconnect_interval}ms (attempt #{state.reconnect_attempts + 1})"
      )

      Process.sleep(@reconnect_interval)
      {:reconnect, %{state | reconnect_attempts: state.reconnect_attempts + 1}}
    else
      Logger.error("[UnifiClient.WebSocket] Max reconnect attempts reached, giving up")
      {:ok, state}
    end
  end

  @impl WebSockex
  def terminate(reason, _state) do
    Logger.info("[UnifiClient.WebSocket] Terminating: #{inspect(reason)}")
    :ok
  end

  # Private functions

  defp build_websocket_url(%UnifiClient.Client{} = client, site) do
    host = client.host
    port = client.port
    prefix = UnifiClient.Client.api_prefix(client)

    "wss://#{host}:#{port}#{prefix}/wss/s/#{site}/events"
  end

  defp get_cookies(%UnifiClient.Client{cookie_jar: jar}) do
    jar
    |> UnifiClient.CookieJar.get_cookies()
    |> Enum.map(&extract_name_value/1)
    |> Enum.join("; ")
  end

  defp extract_name_value(cookie) do
    cookie
    |> String.split(";")
    |> List.first()
    |> String.trim()
  end

  defp ssl_options(%UnifiClient.Client{verify_ssl: true}), do: []

  defp ssl_options(%UnifiClient.Client{verify_ssl: false}) do
    [verify: :verify_none]
  end

  defp broadcast_event(subscribers, event) do
    Enum.each(subscribers, fn pid ->
      send(pid, {:unifi_event, event})
    end)
  end
end
