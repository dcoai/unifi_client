defmodule UnifiClient.API.Statistics do
  @moduledoc """
  API operations for statistics and metrics.

  This module provides access to various statistics including
  bandwidth usage, DPI (Deep Packet Inspection) data, and
  historical metrics.

  ## Examples

      {:ok, stats} = UnifiClient.API.Statistics.daily_site(client, "default")
      {:ok, dpi} = UnifiClient.API.Statistics.dpi(client, "default")

  """

  alias UnifiClient.{Client, API, Error}

  @doc """
  Gets hourly site statistics for the past 7 days.

  ## Parameters

    * `site` - The site name (e.g., "default")
    * `opts` - Options
      * `:start` - Start timestamp (Unix epoch in seconds)
      * `:end` - End timestamp (Unix epoch in seconds)
      * `:attrs` - List of attributes to include

  """
  @spec hourly_site(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def hourly_site(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("hourly", opts)
    API.post(client, site_path(client, site, "/stat/report/hourly.site"), body)
  end

  @doc """
  Gets daily site statistics for the past year.

  ## Parameters

    * `site` - The site name
    * `opts` - Same as hourly_site/3

  """
  @spec daily_site(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def daily_site(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("daily", opts)
    API.post(client, site_path(client, site, "/stat/report/daily.site"), body)
  end

  @doc """
  Gets monthly site statistics.

  ## Parameters

    * `site` - The site name
    * `opts` - Same as hourly_site/3

  """
  @spec monthly_site(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def monthly_site(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("monthly", opts)
    API.post(client, site_path(client, site, "/stat/report/monthly.site"), body)
  end

  @doc """
  Gets hourly access point statistics.

  ## Parameters

    * `site` - The site name
    * `opts` - Options
      * `:mac` - Filter by AP MAC address
      * `:start` - Start timestamp
      * `:end` - End timestamp

  """
  @spec hourly_ap(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def hourly_ap(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("hourly", opts)
    API.post(client, site_path(client, site, "/stat/report/hourly.ap"), body)
  end

  @doc """
  Gets daily access point statistics.

  ## Parameters

    * `site` - The site name
    * `opts` - Same as hourly_ap/3

  """
  @spec daily_ap(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def daily_ap(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("daily", opts)
    API.post(client, site_path(client, site, "/stat/report/daily.ap"), body)
  end

  @doc """
  Gets hourly user (client) statistics.

  ## Parameters

    * `site` - The site name
    * `opts` - Options
      * `:mac` - Filter by client MAC address
      * `:start` - Start timestamp
      * `:end` - End timestamp

  """
  @spec hourly_user(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def hourly_user(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("hourly", opts)
    API.post(client, site_path(client, site, "/stat/report/hourly.user"), body)
  end

  @doc """
  Gets daily user (client) statistics.

  ## Parameters

    * `site` - The site name
    * `opts` - Same as hourly_user/3

  """
  @spec daily_user(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def daily_user(%Client{} = client, site, opts \\ []) do
    body = build_stat_params("daily", opts)
    API.post(client, site_path(client, site, "/stat/report/daily.user"), body)
  end

  @doc """
  Gets DPI (Deep Packet Inspection) statistics.

  Returns application-level traffic data.

  ## Parameters

    * `site` - The site name

  """
  @spec dpi(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def dpi(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/dpi"))
  end

  @doc """
  Gets DPI statistics for a specific time period.

  ## Parameters

    * `site` - The site name
    * `type` - Time period: "by_cat" (category) or "by_app" (application)
    * `opts` - Options
      * `:start` - Start timestamp
      * `:end` - End timestamp

  """
  @spec dpi_stats(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def dpi_stats(%Client{} = client, site, type \\ "by_cat", opts \\ []) do
    body =
      %{
        "type" => type
      }
      |> maybe_add(:start, opts[:start])
      |> maybe_add(:end, opts[:end])

    API.post(client, site_path(client, site, "/stat/sitedpi"), body)
  end

  @doc """
  Gets current speedtest results.

  ## Parameters

    * `site` - The site name

  """
  @spec speedtest_results(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def speedtest_results(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/speedtest-results"))
  end

  @doc """
  Gets IPS/IDS events (Intrusion Prevention/Detection).

  ## Parameters

    * `site` - The site name
    * `opts` - Options
      * `:start` - Start timestamp
      * `:end` - End timestamp
      * `:limit` - Maximum number of results

  """
  @spec ips_events(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def ips_events(%Client{} = client, site, opts \\ []) do
    body =
      %{}
      |> maybe_add(:start, opts[:start])
      |> maybe_add(:end, opts[:end])
      |> maybe_add(:_limit, opts[:limit])

    API.post(client, site_path(client, site, "/stat/ips/event"), body)
  end

  @doc """
  Gets routing table.

  ## Parameters

    * `site` - The site name

  """
  @spec routing(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def routing(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/routing"))
  end

  @doc """
  Gets current dashboard metrics.

  ## Parameters

    * `site` - The site name

  """
  @spec dashboard(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def dashboard(%Client{} = client, site) do
    API.get_one(client, site_path(client, site, "/stat/dashboard"))
  end

  # Private helpers

  defp site_path(%Client{} = client, site, path) do
    Client.site_url(client, site, path)
  end

  defp build_stat_params(_type, opts) do
    %{}
    |> maybe_add(:start, opts[:start])
    |> maybe_add(:end, opts[:end])
    |> maybe_add(:mac, opts[:mac] && String.downcase(opts[:mac]))
    |> maybe_add(:attrs, opts[:attrs])
  end

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, to_string(key), value)
end
