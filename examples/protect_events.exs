# Stream live UniFi Protect updates (motion, smart detections, camera state)
#
# Usage:
#   UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret elixir examples/protect_events.exs
#
# Prints one line per update until Ctrl-C. Pass --resume <lastUpdateId> (printed
# on connect and with every event) to continue from an earlier cursor without
# replaying what was already seen.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule ProtectEvents do
  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    {opts, _rest, invalid} = OptionParser.parse(System.argv(), strict: [resume: :string])

    if invalid != [] do
      IO.puts("Invalid options: #{inspect(invalid)}")
      print_help()
      System.halt(1)
    end

    host = System.get_env("UNIFI_HOST") || raise "UNIFI_HOST environment variable required"
    username = System.get_env("UNIFI_USER") || raise "UNIFI_USER environment variable required"
    password = System.get_env("UNIFI_PASS") || raise "UNIFI_PASS environment variable required"

    IO.puts("Connecting to #{host}...")

    {:ok, client} =
      UnifiClient.Client.new(host: host, username: username, password: password, verify_ssl: false)

    IO.puts("Logging in...")
    {:ok, client} = UnifiClient.Auth.login(client)

    # Camera names make the stream readable; ids are what the events carry.
    {:ok, cameras} = UnifiClient.Protect.Cameras.list(client)
    names = Map.new(cameras, fn cam -> {cam["id"], cam["name"] || cam["id"]} end)

    ws_opts = [client: client, subscriber: self()]
    ws_opts = if opts[:resume], do: Keyword.put(ws_opts, :last_update_id, opts[:resume]), else: ws_opts

    case UnifiClient.Protect.WebSocket.start_link(ws_opts) do
      {:ok, _ws} ->
        IO.puts("Streaming updates (Ctrl-C to stop)...\n")
        loop(names)

      {:error, error} ->
        IO.puts("Could not connect: #{inspect(error)}")
        UnifiClient.Auth.logout(client)
        System.halt(1)
    end
  end

  defp loop(names) do
    receive do
      {:unifi_protect_event, %{action: action, data: data}} ->
        print_event(action, data, names)
        loop(names)
    end
  end

  defp print_event(action, data, names) do
    stamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    model = action["modelKey"]
    id = action["id"]
    subject = if model == "camera", do: Map.get(names, id, id), else: id
    changed = if is_map(data), do: data |> Map.keys() |> Enum.sort() |> Enum.join(","), else: inspect(data)

    IO.puts(
      "#{stamp}  #{String.pad_trailing(model || "?", 12)} #{String.pad_trailing(action["action"] || "?", 7)} " <>
        "#{String.pad_trailing(subject, 24)} #{changed}  [lastUpdateId=#{action["newUpdateId"]}]"
    )

    if model == "camera" and Map.has_key?(data, "isMotionDetected") do
      IO.puts("           motion #{if data["isMotionDetected"], do: "started", else: "ended"} on #{subject}")
    end
  end

  defp help_requested? do
    System.argv() |> Enum.any?(&(&1 in ["-h", "--help"]))
  end

  defp print_help do
    IO.puts("""
    Stream live UniFi Protect updates (motion, smart detections, camera state)

    Usage:
      elixir examples/protect_events.exs [--resume <lastUpdateId>]

    Environment variables (required):
      UNIFI_HOST       UniFi OS console hostname or IP (UDM, UNVR, UCG, ...)
      UNIFI_USER       Username
      UNIFI_PASS       Password

    Options:
      --resume ID      Continue from a previously printed lastUpdateId
      -h, --help       Show this help
    """)
  end
end

ProtectEvents.run()
