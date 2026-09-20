# Export recorded video from one or more UniFi Protect cameras to MP4
#
# Usage:
#   UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \
#     elixir examples/protect_export.exs --camera <camera-id> \
#       --start 2026-09-17T08:00:00Z --end 2026-09-17T08:01:00Z --out porch.mp4 \
#       [--type rotating|timelapse] [--channel 0|1|2]
#
#   # several cameras, same window, one file each under a directory
#   ... --camera id1,id2,id3 --out clips/ [--channel 1] [--concurrency 2]
#
# Camera ids come from examples/protect_cameras.exs. Times are ISO 8601 with a
# zone (a trailing Z for UTC). The console renders the clip on demand, so the
# request takes roughly as long as the clip; the script prints the timeout it
# will wait before starting.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule ProtectExport do
  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    {opts, _rest, invalid} =
      OptionParser.parse(System.argv(),
        strict: [
          camera: :string,
          start: :string,
          end: :string,
          out: :string,
          type: :string,
          channel: :integer,
          concurrency: :integer
        ]
      )

    if invalid != [] do
      IO.puts("Invalid options: #{inspect(invalid)}")
      print_help()
      System.halt(1)
    end

    cameras = require_opt(opts, :camera) |> String.split(",", trim: true)
    start = parse_time(require_opt(opts, :start), "--start")
    finish = parse_time(require_opt(opts, :end), "--end")
    out = require_opt(opts, :out)
    type = parse_type(opts[:type])

    host = System.get_env("UNIFI_HOST") || raise "UNIFI_HOST environment variable required"
    username = System.get_env("UNIFI_USER") || raise "UNIFI_USER environment variable required"
    password = System.get_env("UNIFI_PASS") || raise "UNIFI_PASS environment variable required"

    IO.puts("Connecting to #{host}...")

    {:ok, client} =
      UnifiClient.Client.new(host: host, username: username, password: password, verify_ssl: false)

    IO.puts("Logging in...")
    {:ok, client} = UnifiClient.Auth.login(client)

    clip_s = DateTime.diff(finish, start, :second)
    timeout_ms = UnifiClient.Protect.Video.export_timeout(client, start, finish)
    export_opts = [type: type] ++ if(opts[:channel], do: [channel: opts[:channel]], else: [])

    IO.puts(
      "Exporting #{clip_s}s of #{type} footage from #{Enum.join(cameras, ", ")} -> #{out} " <>
        "(will wait up to #{div(timeout_ms, 1000)}s per clip)..."
    )

    started = System.monotonic_time(:millisecond)
    result = run_export(client, cameras, start, finish, out, export_opts, opts[:concurrency])
    UnifiClient.Auth.logout(client)
    elapsed = System.monotonic_time(:millisecond) - started

    report(result, elapsed)
  end

  defp run_export(client, [camera], start, finish, out, export_opts, _concurrency) do
    UnifiClient.Protect.Video.export(client, camera, start, finish, out, export_opts)
  end

  defp run_export(client, cameras, start, finish, dir, export_opts, concurrency) do
    many_opts = if concurrency, do: [max_concurrency: concurrency], else: []
    UnifiClient.Protect.Video.export_many(client, cameras, start, finish, dir, many_opts ++ export_opts)
  end

  defp report({:ok, path}, elapsed) when is_binary(path) do
    IO.puts("Wrote #{File.stat!(path).size} bytes to #{path} in #{elapsed}ms")
  end

  defp report({:ok, results}, elapsed) when is_list(results) do
    Enum.each(results, fn
      {id, {:ok, path}} -> IO.puts("  #{id}: #{File.stat!(path).size} bytes -> #{path}")
      {id, {:error, error}} -> IO.puts("  #{id}: FAILED #{error.message}")
    end)

    failed = Enum.count(results, &match?({_, {:error, _}}, &1))
    IO.puts("#{length(results) - failed}/#{length(results)} exports succeeded in #{elapsed}ms")
    if failed > 0, do: System.halt(1)
  end

  defp report({:error, error}, elapsed) do
    IO.puts("Export failed after #{elapsed}ms: #{error.message}")
    System.halt(1)
  end

  defp require_opt(opts, key) do
    opts[key] ||
      (
        IO.puts("--#{key} is required")
        print_help()
        System.halt(1)
      )
  end

  defp parse_time(str, flag) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        dt

      {:error, reason} ->
        IO.puts("#{flag}: #{str} is not an ISO 8601 datetime with zone (#{reason})")
        System.halt(1)
    end
  end

  defp parse_type(nil), do: :rotating
  defp parse_type("rotating"), do: :rotating
  defp parse_type("timelapse"), do: :timelapse

  defp parse_type(other) do
    IO.puts("--type must be rotating or timelapse, got #{other}")
    System.halt(1)
  end

  defp help_requested? do
    System.argv() |> Enum.any?(&(&1 in ["-h", "--help"]))
  end

  defp print_help do
    IO.puts("""
    Export recorded video from one or more UniFi Protect cameras to MP4

    Usage:
      elixir examples/protect_export.exs --camera <id> --start <iso8601> --end <iso8601> --out <file.mp4> [options]
      elixir examples/protect_export.exs --camera <id1,id2,...> --start <iso8601> --end <iso8601> --out <dir> [options]

    Environment variables (required):
      UNIFI_HOST       UniFi OS console hostname or IP (UDM, UNVR, UCG, ...)
      UNIFI_USER       Username
      UNIFI_PASS       Password

    Options:
      --camera IDS     Camera id, or several comma-separated (see examples/protect_cameras.exs)
      --start TIME     Clip start, ISO 8601 with zone, e.g. 2026-09-17T08:00:00Z
      --end TIME       Clip end, same format, after --start
      --out PATH       The MP4 file for one camera; a directory (<id>.mp4 each) for several
      --type TYPE      rotating (default) or timelapse
      --channel N      Stream to export: 0 high, 1 medium, 2 low (default: console's choice)
      --concurrency N  Exports in flight at once for several cameras (default 2)
      -h, --help       Show this help
    """)
  end
end

ProtectExport.run()
