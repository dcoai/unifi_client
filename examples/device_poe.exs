# Set PoE state for ports on a UniFi switch
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret \
#     elixir device_poe.exs <device_ip> <on|off> <port1,port2,...>
#
# Examples:
#   elixir device_poe.exs 10.0.1.10 off 1,2,3
#   elixir device_poe.exs 10.0.1.10 on 5-8
#   elixir device_poe.exs 10.0.1.10 on 1,3,5-7
#
# Optional environment variables:
#   UNIFI_SITE - site name (default: "default")
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")

Mix.install([
  {:unifi_client, path: "../unifi"}
])

defmodule DevicePoe do
  def run do
    {device_ip, poe_state, ports} = parse_args()

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

    IO.puts("Finding device with IP #{device_ip}...")
    {:ok, devices} = UnifiClient.API.Devices.list(client, site)

    device = Enum.find(devices, fn d -> d["ip"] == device_ip end)

    if device == nil do
      IO.puts("Error: No device found with IP #{device_ip}")
      UnifiClient.Auth.logout(client)
      System.halt(1)
    end

    device_id = device["_id"]
    device_name = device["name"] || "(unnamed)"
    device_type = device["type"]

    if device_type not in ["usw", "udm"] do
      IO.puts("Error: Device '#{device_name}' is not a switch (type: #{device_type})")
      UnifiClient.Auth.logout(client)
      System.halt(1)
    end

    poe_mode = if poe_state == :on, do: "auto", else: "off"
    state_str = if poe_state == :on, do: "ON", else: "OFF"
    ports_str = Enum.join(ports, ", ")

    IO.puts("Setting PoE #{state_str} on ports [#{ports_str}] for '#{device_name}'...")

    case UnifiClient.API.Devices.set_poe_mode(client, site, device_id, ports, poe_mode) do
      {:ok, _} ->
        IO.puts("Success!")

      {:error, error} ->
        IO.puts("Error: #{inspect(error)}")
        UnifiClient.Auth.logout(client)
        System.halt(1)
    end

    UnifiClient.Auth.logout(client)
  end

  defp parse_args do
    case System.argv() do
      [device_ip, state, ports_str] ->
        poe_state = parse_poe_state(state)
        ports = parse_ports(ports_str)
        {device_ip, poe_state, ports}

      _ ->
        IO.puts("Usage: elixir device_poe.exs <device_ip> <on|off> <ports>")
        IO.puts("")
        IO.puts("Ports can be individual numbers or ranges separated by commas:")
        IO.puts("  1,2,3    - ports 1, 2, and 3")
        IO.puts("  5-8      - ports 5, 6, 7, and 8")
        IO.puts("  1,3,5-7  - ports 1, 3, 5, 6, and 7")
        IO.puts("")
        IO.puts("Examples:")
        IO.puts("  elixir device_poe.exs 10.0.1.10 off 1,2,3")
        IO.puts("  elixir device_poe.exs 10.0.1.10 on 5-8")
        IO.puts("  elixir device_poe.exs 10.0.1.10 on 1,3,5-7")
        System.halt(1)
    end
  end

  defp parse_poe_state("on"), do: :on
  defp parse_poe_state("off"), do: :off
  defp parse_poe_state(other) do
    IO.puts("Error: Invalid PoE state '#{other}'. Use 'on' or 'off'.")
    System.halt(1)
  end

  defp parse_ports(ports_str) do
    ports_str
    |> String.split(",")
    |> Enum.flat_map(&parse_port_or_range/1)
    |> Enum.sort()
    |> Enum.uniq()
  end

  defp parse_port_or_range(str) do
    str = String.trim(str)

    case String.split(str, "-") do
      [single] ->
        [parse_single_port(single)]

      [start_str, end_str] ->
        start_port = parse_single_port(start_str)
        end_port = parse_single_port(end_str)

        if start_port > end_port do
          IO.puts("Error: Invalid port range '#{str}' (start > end)")
          System.halt(1)
        end

        Enum.to_list(start_port..end_port)

      _ ->
        IO.puts("Error: Invalid port specification '#{str}'")
        System.halt(1)
    end
  end

  defp parse_single_port(str) do
    case Integer.parse(String.trim(str)) do
      {port, ""} when port > 0 -> port
      _ ->
        IO.puts("Error: Invalid port number '#{str}'")
        System.halt(1)
    end
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller
  defp parse_type(other), do: raise "Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'."
end

DevicePoe.run()
