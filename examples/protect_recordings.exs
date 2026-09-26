# List what UniFi Protect recorded in a window, and fetch an event's
# thumbnail or motion heatmap
#
# Usage:
#   UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \
#     elixir examples/protect_recordings.exs [hours] [--type motion,ring] [--limit 50]
#
#   UNIFI_HOST=... elixir examples/protect_recordings.exs --thumbnail <event-id> --out shot.jpg
#   UNIFI_HOST=... elixir examples/protect_recordings.exs --heatmap <event-id> --out heat.png
#
#   hours - how far back to look (default: 1)
#
# This is the *recorded* half of Protect events. For the live stream of
# updates as they happen, see protect_watch.exs.
#
# Protect only exists on UniFi OS consoles, so UNIFI_TYPE is always udm_pro.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule ProtectRecordings do
  alias UnifiClient.Protect

  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    {opts, rest, _bad} =
      OptionParser.parse(System.argv(),
        strict: [
          type: :string,
          limit: :integer,
          thumbnail: :string,
          heatmap: :string,
          out: :string
        ]
      )

    client = connect()

    case {opts[:thumbnail], opts[:heatmap]} do
      {nil, nil} -> list_events(client, hours(rest), opts)
      {id, nil} -> download(client, :thumbnail, id, opts[:out] || "thumbnail.jpg")
      {nil, id} -> download(client, :heatmap, id, opts[:out] || "heatmap.png")
      {_, _} -> IO.puts("Choose one of --thumbnail or --heatmap, not both.")
    end

    IO.puts("\nDone.")
  end

  defp list_events(client, hours, opts) do
    now = DateTime.utc_now()
    from = DateTime.add(now, -hours * 3600, :second)

    # `start`/`end` take a DateTime or epoch milliseconds; `types` and
    # `limit` are passed only when given, and the console defaults the rest.
    query =
      [start: from, end: now]
      |> put_unless_nil(:types, types(opts[:type]))
      |> put_unless_nil(:limit, opts[:limit])

    IO.puts(
      "Events in the last #{hours} hour(s)#{if opts[:type], do: " of type #{opts[:type]}", else: ""}\n"
    )

    case Protect.Events.list(client, query) do
      {:ok, []} ->
        IO.puts("(nothing recorded in that window)")

      {:ok, events} ->
        IO.puts(String.duplicate("-", 78))

        for event <- events do
          IO.puts(
            "#{at(event["start"])}  #{String.pad_trailing(event["type"] || "?", 18)} #{camera(event)}"
          )

          IO.puts("  id #{event["id"]}#{smart(event)}#{score(event)}")
        end

        IO.puts(String.duplicate("-", 78))
        IO.puts("#{length(events)} event(s). Fetch one's picture with:")
        IO.puts("  elixir examples/protect_recordings.exs --thumbnail <id> --out shot.jpg")

      {:error, error} ->
        IO.puts("Error listing events: #{error.message}")
    end
  end

  defp download(client, kind, event_id, out) do
    IO.puts("Fetching #{kind} for #{event_id} -> #{out}...")

    # `dest:` a path streams straight to the file; :memory (the default)
    # would hand back the bytes instead.
    result =
      case kind do
        :thumbnail -> Protect.Events.thumbnail(client, event_id, dest: out)
        :heatmap -> Protect.Events.heatmap(client, event_id, dest: out)
      end

    case result do
      {:ok, path} ->
        IO.puts("Wrote #{path} (#{File.stat!(path).size} bytes)")

      {:error, error} ->
        IO.puts("Error: #{error.message}")
        IO.puts("(not every event has one — a heatmap needs a camera that records motion zones)")
    end
  end

  defp types(nil), do: nil
  defp types(list), do: String.split(list, ",", trim: true)

  defp put_unless_nil(query, _key, nil), do: query
  defp put_unless_nil(query, key, value), do: Keyword.put(query, key, value)

  defp camera(event), do: event["camera"] || event["cameraId"] || "(no camera)"

  defp smart(%{"smartDetectTypes" => [_ | _] = types}), do: "  #{Enum.join(types, ", ")}"
  defp smart(_event), do: ""

  defp score(%{"score" => score}) when is_number(score), do: "  score #{score}"
  defp score(_event), do: ""

  # Protect timestamps are epoch milliseconds.
  defp at(nil), do: "(no start)        "

  defp at(ms) when is_number(ms) do
    ms |> DateTime.from_unix!(:millisecond) |> Calendar.strftime("%Y-%m-%d %H:%M:%S")
  end

  defp hours(rest) do
    case rest do
      [hours | _] ->
        case Integer.parse(hours) do
          {n, ""} when n > 0 -> n
          _ -> raise "hours must be a positive whole number, got #{inspect(hours)}"
        end

      [] ->
        1
    end
  end

  # --- the shape every example shares ---------------------------------------

  defp connect do
    host = System.get_env("UNIFI_HOST") || raise "UNIFI_HOST environment variable required"
    username = System.get_env("UNIFI_USER") || raise "UNIFI_USER environment variable required"
    password = System.get_env("UNIFI_PASS") || raise "UNIFI_PASS environment variable required"

    {:ok, client} =
      UnifiClient.Client.new(
        host: host,
        username: username,
        password: password,
        type: :udm_pro,
        verify_ssl: false
      )

    case UnifiClient.Auth.login(client) do
      {:ok, client} ->
        client

      {:error, error} ->
        IO.puts("Login failed: #{error.message}")
        System.halt(1)
    end
  end

  defp help_requested?, do: Enum.any?(System.argv(), &(&1 in ["-h", "--help"]))

  defp print_help do
    IO.puts("""
    List UniFi Protect's recorded events, and fetch an event's picture

    Usage:
      elixir examples/protect_recordings.exs [hours] [--type motion,ring] [--limit 50]
      elixir examples/protect_recordings.exs --thumbnail <event-id> --out shot.jpg
      elixir examples/protect_recordings.exs --heatmap <event-id> --out heat.png

      hours            How far back to look (default: 1)
      --type           Comma-separated event types: motion, ring, smartDetectZone…
      --limit          Most events to return
      --thumbnail      Save the JPEG Protect rendered for an event
      --heatmap        Save the PNG motion heatmap for an event
      --out            Where to write it

    Environment variables (required):
      UNIFI_HOST       UniFi OS console hostname or IP
      UNIFI_USER       Username for authentication
      UNIFI_PASS       Password for authentication

    This is the recorded half of Protect events. For updates as they happen,
    see protect_watch.exs.

    Example:
      UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \\
        elixir examples/protect_recordings.exs 6 --type motion
    """)
  end
end

ProtectRecordings.run()
