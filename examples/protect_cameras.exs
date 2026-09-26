# List UniFi Protect cameras, optionally saving a snapshot from one
#
# Usage:
#   UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret elixir examples/protect_cameras.exs
#   UNIFI_HOST=unvr.local UNIFI_USER=admin UNIFI_PASS=secret \
#     elixir examples/protect_cameras.exs --snapshot <camera-id> --out porch.jpg [--width 640]
#
# Protect only exists on UniFi OS consoles, so UNIFI_TYPE is always udm_pro here.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule ProtectCameras do
  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    {opts, _rest, invalid} =
      OptionParser.parse(System.argv(),
        strict: [snapshot: :string, out: :string, width: :integer]
      )

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
      UnifiClient.Client.new(
        host: host,
        username: username,
        password: password,
        verify_ssl: false
      )

    IO.puts("Logging in...")

    client =
      case UnifiClient.Auth.login(client) do
        {:ok, client} ->
          client

        {:error, error} ->
          IO.puts("Login failed: #{error.message}")
          System.halt(1)
      end

    case UnifiClient.Protect.Cameras.list(client) do
      {:ok, cameras} ->
        print_cameras(cameras)
        maybe_snapshot(client, opts)

      {:error, error} ->
        IO.puts("Error listing cameras: #{error.message}")
        UnifiClient.Auth.logout(client)
        System.halt(1)
    end

    UnifiClient.Auth.logout(client)
  end

  defp print_cameras(cameras) do
    IO.puts("\nFound #{length(cameras)} camera(s):\n")

    IO.puts(
      String.pad_trailing("ID", 26) <>
        String.pad_trailing("Name", 22) <>
        String.pad_trailing("Type", 16) <>
        String.pad_trailing("State", 14) <> "Recording"
    )

    IO.puts(String.duplicate("-", 90))

    Enum.each(cameras, fn cam ->
      IO.puts(
        String.pad_trailing(cam["id"] || "?", 26) <>
          String.pad_trailing(cam["name"] || "(unnamed)", 22) <>
          String.pad_trailing(cam["type"] || "?", 16) <>
          String.pad_trailing(cam["state"] || "?", 14) <>
          to_string(get_in(cam, ["recordingSettings", "mode"]) || "?")
      )
    end)
  end

  defp maybe_snapshot(client, opts) do
    case {opts[:snapshot], opts[:out]} do
      {nil, _} ->
        :ok

      {_id, nil} ->
        IO.puts("\n--snapshot needs --out <file>")
        System.halt(1)

      {id, out} ->
        IO.puts("\nFetching snapshot from #{id} -> #{out}...")

        case UnifiClient.Protect.Cameras.snapshot(client, id, dest: out, w: opts[:width]) do
          {:ok, ^out} ->
            IO.puts("Wrote #{File.stat!(out).size} bytes to #{out}")

          {:error, error} ->
            IO.puts("Snapshot failed: #{error.message}")
            System.halt(1)
        end
    end
  end

  defp help_requested? do
    System.argv() |> Enum.any?(&(&1 in ["-h", "--help"]))
  end

  defp print_help do
    IO.puts("""
    List UniFi Protect cameras, optionally saving a snapshot from one

    Usage:
      elixir examples/protect_cameras.exs
      elixir examples/protect_cameras.exs --snapshot <camera-id> --out <file.jpg> [--width <px>]

    Environment variables (required):
      UNIFI_HOST       UniFi OS console hostname or IP (UDM, UNVR, UCG, ...)
      UNIFI_USER       Username
      UNIFI_PASS       Password

    Options:
      --snapshot ID    Camera id (first column of the listing) to snapshot
      --out FILE       Where to write the JPEG
      --width PX       Requested snapshot width
      -h, --help       Show this help
    """)
  end
end

ProtectCameras.run()
