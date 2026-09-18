defmodule UnifiClient.Protect.WebSocket do
  @moduledoc """
  Live updates from Protect over its binary WebSocket.

  Connects to `wss://<console>/proxy/protect/ws/updates?lastUpdateId=<id>`
  with the client's session cookie and delivers every decoded message to
  subscribers as

      {:unifi_protect_event, %{action: action, data: data}}

  where `action` is `%{"action" => "add" | "update" | "remove", "modelKey" =>
  "camera" | "event" | "nvr" | ..., "id" => id, "newUpdateId" => id}` and
  `data` is the changed fields (`update`) or the whole object (`add`).

  `lastUpdateId` is the cursor Protect resumes a subscription from. It is
  read from `UnifiClient.Protect.bootstrap/2` unless given, advanced as
  messages arrive, and used again on reconnect so nothing already
  delivered is replayed.

      {:ok, ws} = UnifiClient.Protect.WebSocket.start_link(client: client, subscriber: self())

      receive do
        {:unifi_protect_event, %{action: %{"modelKey" => "camera"} = action, data: data}} ->
          IO.inspect({action["id"], data["isMotionDetected"]})
      end

  Packet framing is in `UnifiClient.Protect.Frame`; this module only
  buffers bytes across WebSocket frames and routes decoded messages.
  """

  use WebSockex
  require Logger

  alias UnifiClient.{Client, Error, Protect}
  alias UnifiClient.Protect.Frame

  @reconnect_interval 5_000
  @max_reconnect_attempts 10

  defstruct [
    :unifi_client,
    :last_update_id,
    :subscribers,
    reconnect_attempts: 0,
    buffer: <<>>
  ]

  @type t :: %__MODULE__{
          unifi_client: Client.t(),
          last_update_id: String.t(),
          subscribers: [pid()],
          reconnect_attempts: non_neg_integer(),
          buffer: binary()
        }

  @doc """
  Starts the WebSocket client.

  ## Options

    * `:client` - Required. An authenticated `UnifiClient.Client` (`:udm_pro`)
    * `:last_update_id` - Cursor to resume from. When omitted,
      `UnifiClient.Protect.bootstrap/2` is called for the current one.
    * `:bootstrap_opts` - Passed to `bootstrap/2` (e.g. `receive_timeout:`)
    * `:subscriber` - PID to receive events (defaults to the caller)
    * `:name` - Optional process name

  ## Returns

    * `{:ok, pid}`
    * `{:error, %UnifiClient.Error{}}` - bootstrap failed or Protect is
      unavailable on this controller type
    * `{:error, reason}` - the WebSocket connection failed

  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    client = Keyword.fetch!(opts, :client)
    subscriber = Keyword.get(opts, :subscriber, self())
    name = Keyword.get(opts, :name)

    with {:ok, update_id} <- resolve_update_id(client, opts) do
      state = %__MODULE__{
        unifi_client: client,
        last_update_id: update_id,
        subscribers: [subscriber]
      }

      ws_opts = conn_opts(client)
      ws_opts = if name, do: Keyword.put(ws_opts, :name, name), else: ws_opts

      WebSockex.start_link(build_url(client, update_id), __MODULE__, state, ws_opts)
    end
  end

  @doc """
  Subscribes a process to receive `{:unifi_protect_event, event}` messages.
  """
  @spec subscribe(pid(), pid()) :: :ok
  def subscribe(ws, subscriber), do: WebSockex.cast(ws, {:subscribe, subscriber})

  @doc """
  Unsubscribes a process.
  """
  @spec unsubscribe(pid(), pid()) :: :ok
  def unsubscribe(ws, subscriber), do: WebSockex.cast(ws, {:unsubscribe, subscriber})

  @doc """
  Closes the connection and stops the process.
  """
  @spec stop(pid()) :: :ok
  def stop(ws), do: WebSockex.cast(ws, :stop)

  @doc """
  The update-stream URL for a client and cursor.

  ## Example

      iex> {:ok, client} = UnifiClient.Client.new(host: "unvr.local")
      iex> UnifiClient.Protect.WebSocket.build_url(client, "abc-123")
      "wss://unvr.local:443/proxy/protect/ws/updates?lastUpdateId=abc-123"

  """
  @spec build_url(Client.t(), String.t()) :: String.t()
  def build_url(%Client{host: host, port: port} = client, last_update_id) do
    prefix = Client.app_prefix(client, :protect)
    query = URI.encode_query(lastUpdateId: last_update_id)
    "wss://#{host}:#{port}#{prefix}/ws/updates?#{query}"
  end

  @doc """
  Decodes every complete message in `state.buffer <> data`.

  Returns the messages in arrival order and the new state: the cursor
  advanced past each message's `newUpdateId`, and the buffer holding any
  trailing incomplete message. Corrupt data logs a warning and empties the
  buffer, since there is no way to resynchronise inside a packet stream.

  Pure; exposed so the framing logic is testable without a socket.
  """
  @spec handle_binary(binary(), t()) :: {[Frame.message()], t()}
  def handle_binary(data, %__MODULE__{buffer: buffer} = state) do
    drain(buffer <> data, %{state | buffer: <<>>}, [])
  end

  # WebSockex callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info(
      "[UnifiClient.Protect.WebSocket] Connected (lastUpdateId=#{state.last_update_id})"
    )

    {:ok, %{state | reconnect_attempts: 0}}
  end

  @impl WebSockex
  def handle_frame({:binary, data}, state) do
    {messages, state} = handle_binary(data, state)
    Enum.each(messages, &broadcast(state.subscribers, &1))
    {:ok, state}
  end

  def handle_frame({:text, msg}, state) do
    Logger.debug("[UnifiClient.Protect.WebSocket] Ignoring text frame: #{inspect(msg)}")
    {:ok, state}
  end

  def handle_frame({:ping, _}, state), do: {:reply, :pong, state}

  def handle_frame(frame, state) do
    Logger.debug("[UnifiClient.Protect.WebSocket] Received frame: #{inspect(frame)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:subscribe, pid}, state) do
    Process.monitor(pid)
    {:ok, %{state | subscribers: Enum.uniq([pid | state.subscribers])}}
  end

  def handle_cast({:unsubscribe, pid}, state) do
    {:ok, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  def handle_cast(:stop, state), do: {:close, state}

  @impl WebSockex
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    {:ok, %{state | subscribers: List.delete(state.subscribers, pid)}}
  end

  def handle_info(msg, state) do
    Logger.debug("[UnifiClient.Protect.WebSocket] Received info: #{inspect(msg)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("[UnifiClient.Protect.WebSocket] Disconnected: #{inspect(reason)}")

    if state.reconnect_attempts < @max_reconnect_attempts do
      attempt = state.reconnect_attempts + 1

      Logger.info(
        "[UnifiClient.Protect.WebSocket] Reconnecting in #{@reconnect_interval}ms " <>
          "(attempt #{attempt}, resuming from #{state.last_update_id})"
      )

      Process.sleep(@reconnect_interval)

      # Rebuild the connection so the resume cursor is the current one, and
      # start from an empty buffer — a half-received message is gone.
      conn =
        WebSockex.Conn.new(
          build_url(state.unifi_client, state.last_update_id),
          conn_opts(state.unifi_client)
        )

      {:reconnect, conn, %{state | reconnect_attempts: attempt, buffer: <<>>}}
    else
      Logger.error("[UnifiClient.Protect.WebSocket] Max reconnect attempts reached, giving up")
      {:ok, state}
    end
  end

  @impl WebSockex
  def terminate(reason, _state) do
    Logger.info("[UnifiClient.Protect.WebSocket] Terminating: #{inspect(reason)}")
    :ok
  end

  # Private functions

  defp resolve_update_id(%Client{} = client, opts) do
    case Keyword.get(opts, :last_update_id) do
      id when is_binary(id) ->
        {:ok, id}

      nil ->
        with {:ok, %{"lastUpdateId" => id}} <-
               Protect.bootstrap(client, Keyword.get(opts, :bootstrap_opts, [])) do
          {:ok, id}
        else
          {:ok, _bootstrap_without_cursor} ->
            {:error, Error.new("bootstrap has no lastUpdateId", :no_update_id)}

          {:error, _} = error ->
            error
        end
    end
  end

  defp drain(bin, state, acc) do
    case Frame.decode_message(bin) do
      {:ok, %{action: action} = message, rest} ->
        state = %{state | last_update_id: action["newUpdateId"] || state.last_update_id}
        drain(rest, state, [message | acc])

      {:error, :incomplete_header} ->
        {Enum.reverse(acc), %{state | buffer: bin}}

      {:error, {:incomplete_payload, _, _}} ->
        {Enum.reverse(acc), %{state | buffer: bin}}

      {:error, reason} ->
        Logger.warning(
          "[UnifiClient.Protect.WebSocket] Dropping #{byte_size(bin)} undecodable bytes: #{inspect(reason)}"
        )

        {Enum.reverse(acc), %{state | buffer: <<>>}}
    end
  end

  defp conn_opts(%Client{} = client) do
    [
      extra_headers: [{"Cookie", cookie_header(client)}],
      ssl_options: ssl_options(client)
    ]
  end

  defp cookie_header(%Client{cookie_jar: jar}) do
    jar
    |> UnifiClient.CookieJar.get_cookies()
    |> Enum.map(fn cookie -> cookie |> String.split(";") |> List.first() |> String.trim() end)
    |> Enum.join("; ")
  end

  defp ssl_options(%Client{verify_ssl: true}), do: []
  defp ssl_options(%Client{verify_ssl: false}), do: [verify: :verify_none]

  defp broadcast(subscribers, message) do
    Enum.each(subscribers, &send(&1, {:unifi_protect_event, message}))
  end
end
