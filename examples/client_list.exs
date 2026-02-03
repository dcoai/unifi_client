# List network clients
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir client_list.exs [filter]
#
# Filter options:
#   active         - Show only currently connected clients (default)
#   known          - Show all known clients (including disconnected)
#   192.168.1.100  - Match specific IP address
#   192.168.1.0/24 - Match CIDR range
#   aa:bb          - Match partial MAC address
#   <pattern>      - Regex search across name, hostname, IP, MAC
#
# Optional environment variables:
#   UNIFI_SITE - site name (default: "default")
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")

Mix.install([
  {:unifi_client, path: "../unifi"}
])

defmodule ListClients do
  import Bitwise

  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    host = System.get_env("UNIFI_HOST") || raise "UNIFI_HOST environment variable required"
    username = System.get_env("UNIFI_USER") || raise "UNIFI_USER environment variable required"
    password = System.get_env("UNIFI_PASS") || raise "UNIFI_PASS environment variable required"
    site = System.get_env("UNIFI_SITE") || "default"
    type = parse_type(System.get_env("UNIFI_TYPE"))

    arg = List.first(System.argv()) || "active"
    {list_type, filter} = parse_argument(arg)

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

    IO.puts("Fetching #{list_type} clients from site '#{site}'...\n")

    {:ok, clients} =
      case list_type do
        :active -> UnifiClient.API.Clients.list_active(client, site)
        :known -> UnifiClient.API.Clients.list_known(client, site)
      end

    filtered_clients = apply_filter(clients, filter)

    IO.puts("Found #{length(filtered_clients)} client(s)#{filter_description(filter)}:\n")

    rows =
      filtered_clients
      |> Enum.sort_by(fn c -> c["hostname"] || c["name"] || c["mac"] end)
      |> Enum.map(fn c ->
        [
          c["hostname"] || c["name"] || "(unnamed)",
          c["ip"] || "-",
          c["mac"] || "-",
          format_connection(c),
          format_bytes(c["rx_bytes"]),
          format_bytes(c["tx_bytes"])
        ]
      end)

    if length(rows) > 0 do
      headers = ["Name", "IP", "MAC", "Connection", "RX", "TX"]
      print_table(headers, rows)
    end

    UnifiClient.Auth.logout(client)
    IO.puts("")
  end

  defp parse_argument("active"), do: {:active, nil}
  defp parse_argument("known"), do: {:known, nil}

  defp parse_argument(arg) do
    cond do
      # CIDR notation (e.g., 192.168.1.0/24)
      String.contains?(arg, "/") && cidr?(arg) ->
        {:active, {:cidr, parse_cidr(arg)}}

      # Full IP address
      ip_address?(arg) ->
        {:active, {:ip, arg}}

      # Partial MAC address (contains colon or dash)
      mac_pattern?(arg) ->
        {:active, {:mac, String.downcase(arg)}}

      # Otherwise treat as regex pattern
      true ->
        case Regex.compile(arg, [:caseless]) do
          {:ok, regex} -> {:active, {:regex, regex}}
          {:error, _} -> {:active, {:regex, ~r/#{Regex.escape(arg)}/i}}
        end
    end
  end

  defp ip_address?(str) do
    case :inet.parse_address(String.to_charlist(str)) do
      {:ok, _} -> true
      _ -> false
    end
  end

  defp mac_pattern?(str) do
    # Contains : or - and looks like hex characters
    (String.contains?(str, ":") || String.contains?(str, "-")) &&
      Regex.match?(~r/^[a-fA-F0-9:\-]+$/, str)
  end

  defp cidr?(str) do
    case String.split(str, "/") do
      [ip, prefix] ->
        ip_address?(ip) && match?({_, ""}, Integer.parse(prefix))
      _ ->
        false
    end
  end

  defp parse_cidr(str) do
    [ip, prefix_str] = String.split(str, "/")
    {prefix, _} = Integer.parse(prefix_str)
    {:ok, ip_tuple} = :inet.parse_address(String.to_charlist(ip))
    ip_int = ip_to_integer(ip_tuple)
    mask = 0xFFFFFFFF <<< (32 - prefix) &&& 0xFFFFFFFF
    network = ip_int &&& mask
    {network, mask}
  end

  defp ip_to_integer({a, b, c, d}), do: a <<< 24 ||| b <<< 16 ||| c <<< 8 ||| d

  defp apply_filter(clients, nil), do: clients

  defp apply_filter(clients, {:ip, ip}) do
    Enum.filter(clients, fn c -> c["ip"] == ip end)
  end

  defp apply_filter(clients, {:cidr, {network, mask}}) do
    Enum.filter(clients, fn c ->
      case c["ip"] do
        nil -> false
        ip ->
          case :inet.parse_address(String.to_charlist(ip)) do
            {:ok, ip_tuple} ->
              ip_int = ip_to_integer(ip_tuple)
              (ip_int &&& mask) == network
            _ -> false
          end
      end
    end)
  end

  defp apply_filter(clients, {:mac, mac_pattern}) do
    Enum.filter(clients, fn c ->
      case c["mac"] do
        nil -> false
        mac -> String.contains?(String.downcase(mac), mac_pattern)
      end
    end)
  end

  defp apply_filter(clients, {:regex, regex}) do
    Enum.filter(clients, fn c ->
      searchable = [
        c["hostname"],
        c["name"],
        c["ip"],
        c["mac"],
        c["essid"],
        c["oui"]
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")

      Regex.match?(regex, searchable)
    end)
  end

  defp filter_description(nil), do: ""
  defp filter_description({:ip, ip}), do: " matching IP #{ip}"
  defp filter_description({:cidr, _}), do: " in CIDR range"
  defp filter_description({:mac, mac}), do: " matching MAC #{mac}"
  defp filter_description({:regex, regex}), do: " matching /#{regex.source}/"

  defp help_requested? do
    System.argv() |> Enum.any?(&(&1 in ["-h", "--help"]))
  end

  defp print_help do
    IO.puts("""
    List network clients

    Usage:
      elixir client_list.exs [filter]

    Filter options:
      active           Show only currently connected clients (default)
      known            Show all known clients (including disconnected)
      <ip>             Match specific IP address (e.g., 192.168.1.100)
      <cidr>           Match CIDR range (e.g., 192.168.1.0/24)
      <mac>            Match partial MAC address (e.g., aa:bb)
      <pattern>        Regex search across name, hostname, IP, MAC

    Environment variables (required):
      UNIFI_HOST       UniFi controller hostname or IP
      UNIFI_USER       Username for authentication
      UNIFI_PASS       Password for authentication

    Environment variables (optional):
      UNIFI_SITE       Site name (default: "default")
      UNIFI_TYPE       Controller type: "udm_pro" or "controller" (default: "udm_pro")

    Examples:
      elixir client_list.exs
      elixir client_list.exs known
      elixir client_list.exs 192.168.1.0/24
      elixir client_list.exs aa:bb:cc
      elixir client_list.exs iphone
    """)
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller
  defp parse_type(other), do: raise "Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'."

  defp format_connection(client) do
    cond do
      client["is_wired"] -> "Wired"
      client["essid"] -> client["essid"]
      true -> "Wireless"
    end
  end

  defp format_bytes(nil), do: "-"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024, do: "#{Float.round(bytes / 1024 / 1024, 1)} MB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1024 / 1024 / 1024, 1)} GB"

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

ListClients.run()
