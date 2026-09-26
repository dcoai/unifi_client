# Show a site's traffic statistics: hourly, daily, DPI and speed tests
#
# Usage:
#   UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret elixir examples/statistics.exs [hours]
#
#   hours - how far back the hourly report reaches (default: 24)
#
# Optional:
#   UNIFI_SITE - site name (default: "default")
#   UNIFI_TYPE - controller type: "udm_pro" or "controller" (default: "udm_pro")

Mix.install([
  {:unifi_client, path: Path.expand("..", __DIR__)}
])

defmodule Statistics do
  alias UnifiClient.API.Statistics

  def run do
    if help_requested?() do
      print_help()
      System.halt(0)
    end

    hours = hours_argument()
    client = connect()
    site = System.get_env("UNIFI_SITE") || "default"

    # The console takes Unix seconds for these reports, and returns one
    # sample per hour or per day with the bytes each way.
    now = System.system_time(:second)

    hourly(client, site, now - hours * 3600, now, hours)
    daily(client, site, now - 7 * 86_400, now)
    dpi(client, site)
    speedtests(client, site)

    UnifiClient.Auth.logout(client)
    IO.puts("\nDone.")
  end

  defp hourly(client, site, from, to, hours) do
    IO.puts("\nHourly, the last #{hours} hour(s)")
    IO.puts(String.duplicate("=", 72))

    case Statistics.hourly_site(client, site, start: from, end: to) do
      {:ok, samples} -> print_samples(samples)
      {:error, error} -> IO.puts("Error: #{error.message}")
    end
  end

  defp daily(client, site, from, to) do
    IO.puts("\nDaily, the last week")
    IO.puts(String.duplicate("=", 72))

    case Statistics.daily_site(client, site, start: from, end: to) do
      {:ok, samples} -> print_samples(samples)
      {:error, error} -> IO.puts("Error: #{error.message}")
    end
  end

  defp print_samples([]), do: IO.puts("(no samples in that window)")

  defp print_samples(samples) do
    for sample <- Enum.sort_by(samples, &(&1["time"] || 0)) do
      # `time` is epoch milliseconds; the byte counters are floats.
      when_ = sample["time"] |> ms_to_datetime() |> Calendar.strftime("%Y-%m-%d %H:%M")

      IO.puts(
        "#{when_}   rx #{bytes(sample["rx_bytes"])}   tx #{bytes(sample["tx_bytes"])}   clients #{round(sample["num_sta"] || 0)}"
      )
    end
  end

  defp dpi(client, site) do
    IO.puts("\nTraffic by category (DPI)")
    IO.puts(String.duplicate("=", 72))

    case Statistics.dpi_stats(client, site, "by_cat") do
      {:ok, []} ->
        IO.puts("(DPI is off, or has nothing yet)")

      {:ok, stats} ->
        stats
        |> Enum.sort_by(&(-((&1["rx_bytes"] || 0) + (&1["tx_bytes"] || 0))))
        |> Enum.take(10)
        |> Enum.each(fn stat ->
          total = (stat["rx_bytes"] || 0) + (stat["tx_bytes"] || 0)
          IO.puts("category #{stat["cat"] || "?"}   #{bytes(total)}")
        end)

      {:error, error} ->
        IO.puts("Error: #{error.message}")
    end
  end

  defp speedtests(client, site) do
    IO.puts("\nSpeed tests")
    IO.puts(String.duplicate("=", 72))

    case Statistics.speedtest_results(client, site) do
      {:ok, []} ->
        IO.puts("(none recorded)")

      {:ok, results} ->
        results
        |> Enum.sort_by(&(-(&1["time"] || 0)))
        |> Enum.take(5)
        |> Enum.each(fn result ->
          when_ = result["time"] |> ms_to_datetime() |> Calendar.strftime("%Y-%m-%d %H:%M")

          IO.puts(
            "#{when_}   down #{result["xput_download"] || "?"} Mbps   up #{result["xput_upload"] || "?"} Mbps   latency #{result["latency"] || "?"} ms"
          )
        end)

      {:error, error} ->
        IO.puts("Error: #{error.message}")
    end
  end

  defp ms_to_datetime(nil), do: DateTime.from_unix!(0)
  defp ms_to_datetime(ms) when is_number(ms), do: DateTime.from_unix!(trunc(ms), :millisecond)

  defp bytes(nil), do: "-"

  defp bytes(n) when is_number(n) do
    cond do
      n >= 1_000_000_000 -> "#{Float.round(n / 1_000_000_000, 1)} GB"
      n >= 1_000_000 -> "#{Float.round(n / 1_000_000, 1)} MB"
      n >= 1_000 -> "#{Float.round(n / 1_000, 1)} kB"
      true -> "#{round(n)} B"
    end
  end

  defp hours_argument do
    case Enum.reject(System.argv(), &String.starts_with?(&1, "-")) do
      [hours | _] ->
        case Integer.parse(hours) do
          {n, ""} when n > 0 -> n
          _ -> raise "hours must be a positive whole number, got #{inspect(hours)}"
        end

      [] ->
        24
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
    Show a site's traffic statistics

    Usage:
      elixir examples/statistics.exs [hours]

      hours            How far back the hourly report reaches (default: 24)

    Environment variables (required):
      UNIFI_HOST       UniFi controller hostname or IP
      UNIFI_USER       Username for authentication
      UNIFI_PASS       Password for authentication

    Environment variables (optional):
      UNIFI_SITE       Site name (default: "default")
      UNIFI_TYPE       Controller type: "udm_pro" or "controller" (default: "udm_pro")

    Shows hourly and daily site traffic, the top ten DPI categories and the
    most recent speed tests. UnifiClient.API.Statistics also reports per
    access point and per client.

    Example:
      UNIFI_HOST=192.168.1.1 UNIFI_USER=admin UNIFI_PASS=secret \\
        elixir examples/statistics.exs 48
    """)
  end

  defp parse_type(nil), do: :udm_pro
  defp parse_type("udm_pro"), do: :udm_pro
  defp parse_type("controller"), do: :controller

  defp parse_type(other),
    do: raise("Invalid UNIFI_TYPE: #{other}. Use 'udm_pro' or 'controller'.")
end

Statistics.run()
