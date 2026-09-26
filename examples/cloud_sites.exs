# List what the UniFi Cloud Site Manager can see: hosts, their sites, and
# optionally a site's devices and clients
#
# Usage:
#   UNIFI_API_KEY=... elixir examples/cloud_sites.exs
#   UNIFI_API_KEY=... elixir examples/cloud_sites.exs --host <host-id> --site <site-name>
#
# The Cloud API is not the console API: it authenticates with an **API key**
# from unifi.ui.com (account settings), not a console username and password,
# and it reaches consoles through Ubiquiti rather than over your LAN.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule CloudSites do
  alias UnifiClient.Cloud

  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    {opts, _rest, _bad} =
      OptionParser.parse(System.argv(), strict: [host: :string, site: :string])

    api_key =
      System.get_env("UNIFI_API_KEY") || raise "UNIFI_API_KEY environment variable required"

    {:ok, client} = Cloud.Client.new(api_key: api_key)

    case {opts[:host], opts[:site]} do
      {nil, _} -> hosts_and_sites(client)
      {host_id, nil} -> sites_of(client, host_id)
      {host_id, site} -> inventory(client, host_id, site)
    end

    IO.puts("\nDone.")
  end

  # A "host" is a console (a UDM, a Cloud Key, a self-hosted controller)
  # adopted into the account; each one holds sites.
  defp hosts_and_sites(client) do
    IO.puts("Hosts")
    IO.puts(String.duplicate("=", 72))

    case Cloud.Sites.list_hosts(client) do
      {:ok, []} ->
        IO.puts("(no hosts on this account)")

      {:ok, hosts} ->
        for host <- hosts do
          IO.puts("#{name_of(host)}   #{host["id"]}")

          IO.puts(
            "  type       #{get_in(host, ["reportedState", "hardware", "shortname"]) || host["type"] || "?"}"
          )

          IO.puts("  version    #{get_in(host, ["reportedState", "version"]) || "?"}")
          sites_of(client, host["id"], "  ")
        end

      {:error, error} ->
        IO.puts("Error listing hosts: #{message(error)}")
    end
  end

  defp sites_of(client, host_id, indent \\ "") do
    case Cloud.Sites.list_sites(client, host_id) do
      {:ok, []} ->
        IO.puts("#{indent}sites      (none)")

      {:ok, sites} ->
        IO.puts(
          "#{indent}sites      #{Enum.map_join(sites, ", ", &(&1["name"] || &1["siteId"] || "?"))}"
        )

      {:error, error} ->
        IO.puts("#{indent}sites      error: #{message(error)}")
    end
  end

  defp inventory(client, host_id, site) do
    IO.puts("Devices on #{site}")
    IO.puts(String.duplicate("=", 72))

    case Cloud.Devices.list(client, host_id, site) do
      {:ok, devices} ->
        for device <- devices do
          IO.puts(
            "#{device["name"] || "(unnamed)"}   #{device["mac"] || "?"}   #{device["model"] || "?"}"
          )
        end

      {:error, error} ->
        IO.puts("Error: #{message(error)}")
    end

    IO.puts("\nClients on #{site}")
    IO.puts(String.duplicate("=", 72))

    case Cloud.Clients.list(client, host_id, site) do
      {:ok, clients} ->
        for c <- Enum.take(clients, 25) do
          IO.puts(
            "#{c["name"] || c["hostname"] || "(unnamed)"}   #{c["mac"] || "?"}   #{c["ip"] || "-"}"
          )
        end

      {:error, error} ->
        IO.puts("Error: #{message(error)}")
    end
  end

  defp name_of(host) do
    get_in(host, ["reportedState", "hostname"]) || host["hostname"] || host["id"] || "(unnamed)"
  end

  defp message(%{message: message}), do: message
  defp message(other), do: inspect(other)

  defp help_requested?, do: Enum.any?(System.argv(), &(&1 in ["-h", "--help"]))

  defp print_help do
    IO.puts("""
    List what the UniFi Cloud Site Manager can see

    Usage:
      elixir examples/cloud_sites.exs
      elixir examples/cloud_sites.exs --host <host-id> --site <site-name>

    Environment variables (required):
      UNIFI_API_KEY    A Site Manager API key from unifi.ui.com (account settings)

    With no arguments, lists every host on the account and the sites each
    one holds. Given a host id and a site name, lists that site's devices
    and clients.

    The Cloud API authenticates with an API key rather than a console login,
    and reaches consoles through Ubiquiti rather than over your LAN — so it
    works from anywhere, and it is not the API the other examples use.

    Example:
      UNIFI_API_KEY=xxxxxxxx elixir examples/cloud_sites.exs
    """)
  end
end

CloudSites.run()
