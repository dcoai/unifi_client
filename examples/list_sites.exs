# List all UniFi sites
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir list_sites.exs
#
# Optional:
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")

Mix.install([
  {:unifi_client, path: "../unifi"}
])

defmodule ListSites do
  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    host = System.get_env("UNIFI_HOST") || raise "UNIFI_HOST environment variable required"
    username = System.get_env("UNIFI_USER") || raise "UNIFI_USER environment variable required"
    password = System.get_env("UNIFI_PASS") || raise "UNIFI_PASS environment variable required"
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

    IO.puts("Fetching sites...\n")

    case UnifiClient.API.Sites.list(client) do
      {:ok, sites} ->
        IO.puts("Found #{length(sites)} site(s):\n")
        IO.puts(String.duplicate("-", 60))

        for site <- sites do
          name = site["name"] || "(unnamed)"
          desc = site["desc"] || ""
          role = site["role"] || "unknown"

          IO.puts("Name: #{name}")
          IO.puts("Description: #{desc}")
          IO.puts("Role: #{role}")
          IO.puts(String.duplicate("-", 60))
        end

      {:error, error} ->
        IO.puts("Error fetching sites: #{inspect(error)}")
    end

    UnifiClient.Auth.logout(client)
    IO.puts("\nDone.")
  end

  defp help_requested? do
    System.argv() |> Enum.any?(&(&1 in ["-h", "--help"]))
  end

  defp print_help do
    IO.puts("""
    List all UniFi sites

    Usage:
      elixir list_sites.exs

    Environment variables (required):
      UNIFI_HOST       UniFi controller hostname or IP
      UNIFI_USER       Username for authentication
      UNIFI_PASS       Password for authentication

    Environment variables (optional):
      UNIFI_TYPE       Controller type: "udm_pro" or "controller" (default: "udm_pro")

    Example:
      UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir list_sites.exs
    """)
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller
  defp parse_type(other), do: raise "Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'."
end

ListSites.run()
