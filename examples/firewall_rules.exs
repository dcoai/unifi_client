# Show a site's firewall rules and port forwards
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir examples/firewall_rules.exs
#
# Optional:
#   UNIFI_SITE - site name (default: "default")
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")
#
# Read-only. `UnifiClient.API.Firewall` can also create, update, enable,
# disable and delete rules and port forwards; an example that changes a
# firewall by accident is not an example anyone wants, so this one reads.

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule FirewallRules do
  alias UnifiClient.API.Firewall

  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    client = connect()
    site = System.get_env("UNIFI_SITE") || "default"

    rules(client, site)
    port_forwards(client, site)

    UnifiClient.Auth.logout(client)
    IO.puts("\nDone.")
  end

  defp rules(client, site) do
    IO.puts("\nFirewall rules")
    IO.puts(String.duplicate("=", 72))

    case Firewall.list_rules(client, site) do
      {:ok, []} ->
        IO.puts("(none)")

      {:ok, rules} ->
        # The console orders rules within a ruleset, and the order is the
        # rule: the first match wins.
        for rule <- Enum.sort_by(rules, &{&1["ruleset"] || "", &1["rule_index"] || 0}) do
          state = if rule["enabled"] == false, do: "  [disabled]", else: ""

          IO.puts(
            "#{rule["ruleset"] || "?"} ##{rule["rule_index"] || "?"}  #{rule["name"] || "(unnamed)"}#{state}"
          )

          IO.puts("  action     #{rule["action"] || "?"}  #{rule["protocol"] || "all"}")
          IO.puts("  from       #{endpoint(rule, "src")}")
          IO.puts("  to         #{endpoint(rule, "dst")}")
          IO.puts("  id         #{rule["_id"]}")
        end

      {:error, error} ->
        IO.puts("Error listing rules: #{error.message}")
    end
  end

  defp endpoint(rule, side) do
    address = rule["#{side}_address"] || rule["#{side}_networkconf_id"] || "any"
    port = rule["#{side}_port"] || rule["#{side}_firewallgroup_ids"]

    case port do
      nil -> address
      [] -> address
      ports when is_list(ports) -> "#{address} (groups: #{Enum.join(ports, ", ")})"
      port -> "#{address}:#{port}"
    end
  end

  defp port_forwards(client, site) do
    IO.puts("\nPort forwards")
    IO.puts(String.duplicate("=", 72))

    case Firewall.list_port_forwards(client, site) do
      {:ok, []} ->
        IO.puts("(none)")

      {:ok, forwards} ->
        for forward <- Enum.sort_by(forwards, &(&1["name"] || "")) do
          state = if forward["enabled"] == false, do: "  [disabled]", else: ""
          IO.puts("#{forward["name"] || "(unnamed)"}#{state}")

          IO.puts(
            "  #{forward["proto"] || "tcp_udp"}  #{forward["src"] || "any"}:#{forward["dst_port"] || "?"}" <>
              " -> #{forward["fwd"] || "?"}:#{forward["fwd_port"] || forward["dst_port"] || "?"}"
          )

          IO.puts("  id         #{forward["_id"]}")
        end

      {:error, error} ->
        IO.puts("Error listing port forwards: #{error.message}")
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
    Show a site's firewall rules and port forwards

    Usage:
      elixir examples/firewall_rules.exs

    Environment variables (required):
      UNIFI_HOST       UniFi controller hostname or IP
      UNIFI_USER       Username for authentication
      UNIFI_PASS       Password for authentication

    Environment variables (optional):
      UNIFI_SITE       Site name (default: "default")
      UNIFI_TYPE       Controller type: "udm_pro" or "controller" (default: "udm_pro")

    Reads only. UnifiClient.API.Firewall also creates, updates and deletes
    rules and port forwards — see the module documentation.

    Example:
      UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret \\
        elixir examples/firewall_rules.exs
    """)
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller

  defp parse_type(other),
    do: raise("Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'.")
end

FirewallRules.run()
