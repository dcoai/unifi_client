defmodule UnifiClient.Cloud.Sites do
  @moduledoc """
  UniFi Cloud Site Manager API operations.

  Provides access to manage hosts (controllers) and sites
  through the UniFi Cloud platform.

  ## Examples

      {:ok, client} = UnifiClient.Cloud.Client.new(api_key: "your-api-key")
      {:ok, hosts} = UnifiClient.Cloud.Sites.list_hosts(client)
      {:ok, sites} = UnifiClient.Cloud.Sites.list_sites(client, host_id)

  """

  alias UnifiClient.Cloud.{Client, API}
  alias UnifiClient.Error

  @doc """
  Lists all hosts (controllers) accessible to your account.

  A host represents a UniFi controller (Dream Machine, Cloud Key, etc.)
  that is linked to your UniFi account.

  ## Returns

      {:ok, [
        %{
          "id" => "host-uuid",
          "reportedState" => %{
            "mac" => "aa:bb:cc:dd:ee:ff",
            "name" => "Home",
            "hostname" => "unifi.local",
            "version" => "...",
            ...
          },
          ...
        }
      ]}

  """
  @spec list_hosts(Client.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_hosts(%Client{} = client) do
    API.get(client, "/ea/hosts")
  end

  @doc """
  Gets details about a specific host.

  ## Parameters

    * `host_id` - The host UUID

  """
  @spec get_host(Client.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_host(%Client{} = client, host_id) do
    API.get(client, "/ea/hosts/#{host_id}")
  end

  @doc """
  Lists all sites for a specific host.

  ## Parameters

    * `host_id` - The host UUID

  ## Returns

      {:ok, [
        %{
          "name" => "default",
          "desc" => "Default",
          "deviceCount" => 5,
          "health" => [...],
          ...
        }
      ]}

  """
  @spec list_sites(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_sites(%Client{} = client, host_id) do
    API.get(client, "/ea/hosts/#{host_id}/sites")
  end

  @doc """
  Gets details about a specific site.

  ## Parameters

    * `host_id` - The host UUID
    * `site_name` - The site name (e.g., "default")

  """
  @spec get_site(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_site(%Client{} = client, host_id, site_name) do
    API.get(client, "/ea/hosts/#{host_id}/sites/#{site_name}")
  end

  @doc """
  Gets site health information.

  ## Parameters

    * `host_id` - The host UUID
    * `site_name` - The site name

  """
  @spec site_health(Client.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def site_health(%Client{} = client, host_id, site_name) do
    API.get(client, "/ea/hosts/#{host_id}/sites/#{site_name}/health")
  end
end
