defmodule UnifiClient.API.Sites do
  @moduledoc """
  API operations for UniFi sites.

  A site in UniFi represents a logical grouping of devices and configuration.
  Most controllers have at least one site, typically named "default".

  ## Examples

      {:ok, sites} = UnifiClient.API.Sites.list(client)
      {:ok, health} = UnifiClient.API.Sites.health(client, "default")

  """

  alias UnifiClient.{Client, API, Error}

  @doc """
  Lists all sites accessible to the authenticated user.

  ## Returns

      {:ok, [
        %{
          "_id" => "...",
          "name" => "default",
          "desc" => "Default",
          "role" => "admin",
          ...
        }
      ]}

  """
  @spec list(Client.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list(%Client{} = client) do
    API.get_list(client, "/api/self/sites")
  end

  @doc """
  Gets information about a specific site.

  ## Parameters

    * `site` - The site name (e.g., "default")

  """
  @spec get(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, site) do
    case list(client) do
      {:ok, sites} ->
        case Enum.find(sites, fn s -> s["name"] == site end) do
          nil -> {:error, Error.not_found("Site")}
          site_info -> {:ok, site_info}
        end

      error ->
        error
    end
  end

  @doc """
  Gets the health status of a site.

  Returns health metrics for the site including status of subsystems
  like WAN, WLAN, LAN, VPN, etc.

  ## Parameters

    * `site` - The site name (e.g., "default")

  ## Returns

      {:ok, [
        %{
          "subsystem" => "wlan",
          "status" => "ok",
          "num_ap" => 2,
          "num_user" => 10,
          ...
        },
        ...
      ]}

  """
  @spec health(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def health(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/health"))
  end

  @doc """
  Gets system information for a site.

  Returns detailed system information including controller version,
  timezone, and configuration details.

  ## Parameters

    * `site` - The site name (e.g., "default")

  """
  @spec sysinfo(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def sysinfo(%Client{} = client, site) do
    API.get_one(client, site_path(client, site, "/stat/sysinfo"))
  end

  @doc """
  Gets recent events for a site.

  ## Parameters

    * `site` - The site name
    * `opts` - Options
      * `:limit` - Maximum number of events (default: 100)
      * `:start` - Offset for pagination

  """
  @spec events(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def events(%Client{} = client, site, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    start = Keyword.get(opts, :start, 0)

    params = [_limit: limit, _start: start]

    API.get_list(
      client,
      site_path(client, site, "/stat/event") <> "?" <> URI.encode_query(params)
    )
  end

  @doc """
  Gets active alarms for a site.

  ## Parameters

    * `site` - The site name

  """
  @spec alarms(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def alarms(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/alarm"))
  end

  @doc """
  Archives (acknowledges) all alarms for a site.

  ## Parameters

    * `site` - The site name

  """
  @spec archive_alarms(Client.t(), String.t()) :: :ok | {:error, Error.t()}
  def archive_alarms(%Client{} = client, site) do
    API.command(client, site_path(client, site, "/cmd/evtmgr"), %{
      "cmd" => "archive-all-alarms"
    })
  end

  @doc """
  Gets site settings.

  ## Parameters

    * `site` - The site name

  """
  @spec settings(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def settings(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/setting"))
  end

  # Private helpers

  defp site_path(%Client{} = client, site, path) do
    Client.site_url(client, site, path)
  end
end
