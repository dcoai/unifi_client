# Export recorded video from a UniFi Protect camera to an MP4 file
#
# Usage:
#   UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \
#     elixir examples/protect_export.exs --camera <camera-id> \
#       --start 2026-09-17T08:00:00Z --end 2026-09-17T08:01:00Z --out porch.mp4 [--type rotating|timelapse]
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
        strict: [camera: :string, start: :string, end: :string, out: :string, type: :string]
      )

    if invalid != [] do
      IO.puts("Invalid options: #{inspect(invalid)}")
      print_help()
      System.halt(1)
    end

    camera = require_opt(opts, :camera)
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

    IO.puts(
      "Exporting #{clip_s}s of #{type} footage from #{camera} -> #{out} " <>
        "(will wait up to #{div(timeout_ms, 1000)}s)..."
    )

    started = System.monotonic_time(:millisecond)

    result = UnifiClient.Protect.Video.export(client, camera, start, finish, out, type: type)
    UnifiClient.Auth.logout(client)

    elapsed = System.monotonic_time(:millisecond) - started

    case result do
      {:ok, ^out} ->
        IO.puts("Wrote #{File.stat!(out).size} bytes to #{out} in #{elapsed}ms")

      {:error, error} ->
        IO.puts("Export failed after #{elapsed}ms: #{error.message}")
        System.halt(1)
    end
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
    Export recorded video from a UniFi Protect camera to an MP4 file

    Usage:
      elixir examples/protect_export.exs --camera <id> --start <iso8601> --end <iso8601> --out <file.mp4> [--type rotating|timelapse]

    Environment variables (required):
      UNIFI_HOST       UniFi OS console hostname or IP (UDM, UNVR, UCG, ...)
      UNIFI_USER       Username
      UNIFI_PASS       Password

    Options:
      --camera ID      Camera id (see examples/protect_cameras.exs)
      --start TIME     Clip start, ISO 8601 with zone, e.g. 2026-09-17T08:00:00Z
      --end TIME       Clip end, same format, after --start
      --out FILE       Where to write the MP4
      --type TYPE      rotating (default) or timelapse
      -h, --help       Show this help
    """)
  end
end

ProtectExport.run()
