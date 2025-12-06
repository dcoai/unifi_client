defmodule UnifiClient.Cloud.Clients do
  @moduledoc """
  UniFi Cloud API operations for network clients.

  Access client (station) information across your UniFi hosts
  through the cloud API.

  ## Examples

      {:ok, client} = UnifiClient.Cloud.Client.new(api_key: "your-api-key")
      {:ok, clients} = UnifiClient.Cloud.Clients.list(client, host_id, site_name)

  """

  alias UnifiClient.Cloud.{Client, API}
  alias UnifiClient.Error

  @doc """
  Lists all active clients for a site.

  ## Parameters

    * `host_id` - The host UUID
    * `site_name` - The site name (e.g., "default")

  ## Returns

      {:ok, [
        %{
          "mac" => "aa:bb:cc:dd:ee:ff",
          "hostname" => "iPhone",
          "ip" => "192.168.1.100",
          "essid" => "MyNetwork",
          ...
        }
      ]}

  """
  @spec list(Client.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list(%Client{} = client, host_id, site_name) do
    API.get(client, "/ea/hosts/#{host_id}/sites/#{site_name}/clients")
  end

  @doc """
  Gets a specific client by MAC address.

  ## Parameters

    * `host_id` - The host UUID
    * `site_name` - The site name
    * `mac` - The client MAC address

  """
  @spec get(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, host_id, site_name, mac) do
    mac = normalize_mac(mac)
    API.get(client, "/ea/hosts/#{host_id}/sites/#{site_name}/clients/#{mac}")
  end

  # Private helpers

  defp normalize_mac(mac) do
    mac
    |> String.downcase()
    |> String.replace("-", ":")
  end
end
