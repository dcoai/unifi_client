defmodule UnifiClient.WebSocket.Client do
  @moduledoc """
  WebSocket client for real-time UniFi events.

  Connects to the UniFi controller's WebSocket endpoint to receive
  live updates about device status, client connections, and other events.

  This is the **Network** application's event stream, which is JSON.
  Protect has its own, binary and with a resume cursor —
  `UnifiClient.Protect.WebSocket`.

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

  alias UnifiClient.Client
  alias UnifiClient.WebSocket.Base

  @log_prefix "[UnifiClient.WebSocket]"

  defstruct [
    :unifi_client,
    :site,
    :url,
    :subscribers,
    reconnect_attempts: 0
  ]

  @type t :: %__MODULE__{
          unifi_client: Client.t(),
          site: String.t(),
          url: String.t(),
          subscribers: Base.subscribers(),
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

    url = build_url(unifi_client, site)

    state = %__MODULE__{
      unifi_client: unifi_client,
      site: site,
      url: url,
      subscribers: Base.subscribers(subscriber)
    }

    ws_opts = Base.conn_opts(unifi_client)
    ws_opts = if name, do: Keyword.put(ws_opts, :name, name), else: ws_opts

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

  @doc """
  The event-stream URL for a client and site.

  ## Example

      iex> {:ok, client} = UnifiClient.Client.new(host: "udm.local")
      iex> UnifiClient.WebSocket.Client.build_url(client, "default")
      "wss://udm.local:443/proxy/network/wss/s/default/events"

  """
  @spec build_url(Client.t(), String.t()) :: String.t()
  def build_url(%Client{host: host, port: port} = client, site) do
    "wss://#{host}:#{port}#{Client.api_prefix(client)}/wss/s/#{site}/events"
  end

  # WebSockex Callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("#{@log_prefix} Connected to #{state.url}")
    {:ok, %{state | reconnect_attempts: 0, subscribers: Base.monitor_all(state.subscribers)}}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, event} ->
        Base.broadcast(state.subscribers, :unifi_event, event)
        {:ok, state}

      {:error, _} ->
        Logger.warning("#{@log_prefix} Failed to decode message: #{inspect(msg)}")
        {:ok, state}
    end
  end

  def handle_frame({:ping, _}, state) do
    {:reply, :pong, state}
  end

  def handle_frame(frame, state) do
    Logger.debug("#{@log_prefix} Received frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:subscribe, pid}, state) do
    {:ok, %{state | subscribers: Base.subscribe(state.subscribers, pid)}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    {:ok, %{state | subscribers: Base.unsubscribe(state.subscribers, pid)}}
  end

  def handle_cast(:stop, state) do
    {:close, state}
  end

  @impl WebSockex
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:ok, %{state | subscribers: Base.down(state.subscribers, pid)}}
  end

  def handle_info(msg, state) do
    Logger.debug("#{@log_prefix} Received info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("#{@log_prefix} Disconnected: #{inspect(reason)}")
    Base.reconnect(state, state.url, @log_prefix)
  end

  @impl WebSockex
  def terminate(reason, _state) do
    Logger.info("#{@log_prefix} Terminating: #{inspect(reason)}")
    :ok
  end
end
