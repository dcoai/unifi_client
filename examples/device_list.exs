# List all UniFi devices
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir list_devices.exs
#
# Optional:
#   UNIFI_SITE - site name (default: "default")
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")

Mix.install([
  {:unifi_client, path: "../unifi"}
])

defmodule ListDevices do
  def run do
    host = System.get_env("UNIFI_HOST") || raise "UNIFI_HOST environment variable required"
    username = System.get_env("UNIFI_USER") || raise "UNIFI_USER environment variable required"
    password = System.get_env("UNIFI_PASS") || raise "UNIFI_PASS environment variable required"
    site = System.get_env("UNIFI_SITE") || "default"
    type = parse_type(System.get_env("UNIFI_TYPE"))

    IO.puts("Connecting to #{host}...")

    {:ok, client} = UnifiClient.Client.new(
      host: host,
      username: username,
      password: password,
      type: type,
      verify_ssl: false
    )

    IO.puts("Logging in...")
    {:ok, client} = UnifiClient.Auth.login(client)

    IO.puts("Fetching devices from site '#{site}'...\n")
    {:ok, devices} = UnifiClient.API.Devices.list(client, site)

    IO.puts("Found #{length(devices)} device(s):\n")

    rows =
      devices
      |> Enum.sort_by(& &1["name"])
      |> Enum.map(fn device ->
        [
          device["name"] || "(unnamed)",
          device["model"] || "-",
          device["ip"] || "-",
          device["mac"] || "-",
          format_state(device["state"]),
          device["version"] || "-"
        ]
      end)

    headers = ["Name", "Model", "IP", "MAC", "State", "Firmware"]
    print_table(headers, rows)

    UnifiClient.Auth.logout(client)
    IO.puts("")
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller
  defp parse_type(other), do: raise "Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'."

  defp format_state(1), do: "Connected"
  defp format_state(0), do: "Disconnected"
  defp format_state(2), do: "Pending adoption"
  defp format_state(4), do: "Upgrading"
  defp format_state(5), do: "Provisioning"
  defp format_state(6), do: "Heartbeat missed"
  defp format_state(nil), do: "Unknown"
  defp format_state(n), do: "Unknown (#{n})"

  defp print_table(headers, rows) do
    all_rows = [headers | rows]

    widths =
      all_rows
      |> Enum.zip_with(fn column -> column |> Enum.map(&String.length/1) |> Enum.max() end)

    separator = widths |> Enum.map(&String.duplicate("-", &1 + 2)) |> Enum.join("+")
    separator = "+" <> separator <> "+"

    format_row = fn row ->
      cells =
        row
        |> Enum.zip(widths)
        |> Enum.map(fn {cell, width} -> " " <> String.pad_trailing(cell, width) <> " " end)
        |> Enum.join("|")

      "|" <> cells <> "|"
    end

    IO.puts(separator)
    IO.puts(format_row.(headers))
    IO.puts(separator)
    Enum.each(rows, fn row -> IO.puts(format_row.(row)) end)
    IO.puts(separator)
  end
end

ListDevices.run()
