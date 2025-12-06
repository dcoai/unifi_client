defmodule UnifiClient.Cloud.Devices do
  @moduledoc """
  UniFi Cloud API operations for devices.

  Access device information across all your UniFi hosts
  through the cloud API.

  ## Examples

      {:ok, client} = UnifiClient.Cloud.Client.new(api_key: "your-api-key")
      {:ok, devices} = UnifiClient.Cloud.Devices.list(client, host_id, site_name)

  """

  alias UnifiClient.Cloud.{Client, API}
  alias UnifiClient.Error

  @doc """
  Lists all devices for a site.

  ## Parameters

    * `host_id` - The host UUID
    * `site_name` - The site name (e.g., "default")

  ## Returns

      {:ok, [
        %{
          "mac" => "aa:bb:cc:dd:ee:ff",
          "name" => "Office AP",
          "model" => "U6-Pro",
          "type" => "uap",
          "state" => 1,
          ...
        }
      ]}

  """
  @spec list(Client.t(), String.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list(%Client{} = client, host_id, site_name) do
    API.get(client, "/ea/hosts/#{host_id}/sites/#{site_name}/devices")
  end

  @doc """
  Gets a specific device by MAC address.

  ## Parameters

    * `host_id` - The host UUID
    * `site_name` - The site name
    * `mac` - The device MAC address

  """
  @spec get(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, host_id, site_name, mac) do
    mac = normalize_mac(mac)
    API.get(client, "/ea/hosts/#{host_id}/sites/#{site_name}/devices/#{mac}")
  end

  # Private helpers

  defp normalize_mac(mac) do
    mac
    |> String.downcase()
    |> String.replace("-", ":")
  end
end
