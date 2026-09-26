# Show a site's wireless networks and LANs
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir examples/network_config.exs
#
# Optional:
#   UNIFI_SITE - site name (default: "default")
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")
#
# Read-only. `UnifiClient.API.Networks` can also create, update, enable,
# disable and delete WLANs and networks, and set a WLAN's passphrase; none
# of that belongs in an example you might run against a live site by
# accident, so this one only reads.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule NetworkConfig do
  alias UnifiClient.API.Networks

  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    client = connect()
    site = System.get_env("UNIFI_SITE") || "default"

    wlans(client, site)
    networks(client, site)

    UnifiClient.Auth.logout(client)
    IO.puts("\nDone.")
  end

  defp wlans(client, site) do
    IO.puts("\nWireless networks")
    IO.puts(String.duplicate("=", 72))

    case Networks.list_wlans(client, site) do
      {:ok, []} ->
        IO.puts("(none)")

      {:ok, wlans} ->
        for wlan <- Enum.sort_by(wlans, &(&1["name"] || "")) do
          IO.puts(
            "#{wlan["name"] || "(unnamed)"}#{if wlan["enabled"] == false, do: "  [disabled]", else: ""}"
          )

          IO.puts("  security   #{wlan["security"] || "?"}#{wpa(wlan)}")
          IO.puts("  vlan       #{wlan["vlan"] || "untagged"}")
          IO.puts("  id         #{wlan["_id"]}")
        end

      {:error, error} ->
        IO.puts("Error listing WLANs: #{error.message}")
    end
  end

  defp wpa(%{"wpa_mode" => mode}) when is_binary(mode), do: " (#{mode})"
  defp wpa(_wlan), do: ""

  defp networks(client, site) do
    IO.puts("\nNetworks")
    IO.puts(String.duplicate("=", 72))

    case Networks.list_networks(client, site) do
      {:ok, []} ->
        IO.puts("(none)")

      {:ok, networks} ->
        for network <- Enum.sort_by(networks, &(&1["name"] || "")) do
          IO.puts("#{network["name"] || "(unnamed)"}")
          IO.puts("  purpose    #{network["purpose"] || "?"}")
          IO.puts("  subnet     #{network["ip_subnet"] || "-"}")
          IO.puts("  vlan       #{network["vlan"] || "untagged"}")
          IO.puts("  dhcp       #{if network["dhcpd_enabled"], do: "on", else: "off"}")
          IO.puts("  id         #{network["_id"]}")
        end

      {:error, error} ->
        IO.puts("Error listing networks: #{error.message}")
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
        type: parse_type(System.get_env("UNIFI_TYPE")),
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
    Show a site's wireless networks and LANs

    Usage:
      elixir examples/network_config.exs

    Environment variables (required):
      UNIFI_HOST       UniFi controller hostname or IP
      UNIFI_USER       Username for authentication
      UNIFI_PASS       Password for authentication

    Environment variables (optional):
      UNIFI_SITE       Site name (default: "default")
      UNIFI_TYPE       Controller type: "udm_pro" or "controller" (default: "udm_pro")

    Reads only. UnifiClient.API.Networks also creates, updates and deletes
    WLANs and networks — see the module documentation.

    Example:
      UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret \\
        elixir examples/network_config.exs
    """)
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller

  defp parse_type(other),
    do: raise("Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'.")
end

NetworkConfig.run()
