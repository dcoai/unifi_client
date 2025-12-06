defmodule UnifiClient.API.Networks do
  @moduledoc """
  API operations for network configuration.

  This module handles WLANs (wireless networks), LANs, VLANs,
  and other network configurations.

  ## Examples

      {:ok, wlans} = UnifiClient.API.Networks.list_wlans(client, "default")
      {:ok, networks} = UnifiClient.API.Networks.list_networks(client, "default")
      {:ok, wlan} = UnifiClient.API.Networks.create_wlan(client, "default", %{
        name: "Guest",
        security: "wpapsk",
        x_passphrase: "guestpass123"
      })

  """

  alias UnifiClient.{Client, API, Error}

  # ===================
  # WLAN Operations
  # ===================

  @doc """
  Lists all wireless networks (WLANs).

  ## Parameters

    * `site` - The site name (e.g., "default")

  ## Returns

      {:ok, [
        %{
          "_id" => "...",
          "name" => "MyNetwork",
          "enabled" => true,
          "security" => "wpapsk",
          "wpa_mode" => "wpa2",
          ...
        }
      ]}

  """
  @spec list_wlans(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_wlans(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/wlanconf"))
  end

  @doc """
  Gets a specific WLAN by ID.

  ## Parameters

    * `site` - The site name
    * `wlan_id` - The WLAN `_id`

  """
  @spec get_wlan(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_wlan(%Client{} = client, site, wlan_id) do
    API.get_one(client, site_path(client, site, "/rest/wlanconf/#{wlan_id}"))
  end

  @doc """
  Creates a new wireless network (WLAN).

  ## Parameters

    * `site` - The site name
    * `params` - WLAN configuration
      * `:name` - Required. Network name (SSID)
      * `:security` - Security type: "open", "wpapsk", "wpaeap"
      * `:x_passphrase` - WPA passphrase (required for wpapsk)
      * `:wpa_mode` - "wpa2", "wpa3", "wpa2wpa3" (default: "wpa2")
      * `:wpa_enc` - Encryption: "ccmp", "gcmp256" (default: "ccmp")
      * `:enabled` - Whether the WLAN is enabled (default: true)
      * `:hide_ssid` - Hide the SSID (default: false)
      * `:vlan` - VLAN ID for this WLAN
      * `:usergroup_id` - User group ID for bandwidth limits
      * `:wlangroup_id` - WLAN group ID
      * `:ap_group_ids` - List of AP group IDs

  ## Example

      UnifiClient.API.Networks.create_wlan(client, "default", %{
        name: "Guest Network",
        security: "wpapsk",
        x_passphrase: "guestpass123",
        vlan: 100
      })

  """
  @spec create_wlan(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_wlan(%Client{} = client, site, params) do
    body =
      params
      |> normalize_keys()
      |> Map.put_new("enabled", true)
      |> Map.put_new("wpa_mode", "wpa2")
      |> Map.put_new("wpa_enc", "ccmp")

    case API.post(client, site_path(client, site, "/rest/wlanconf"), body) do
      {:ok, [wlan | _]} -> {:ok, wlan}
      {:ok, wlan} when is_map(wlan) -> {:ok, wlan}
      error -> error
    end
  end

  @doc """
  Updates a wireless network configuration.

  ## Parameters

    * `site` - The site name
    * `wlan_id` - The WLAN `_id`
    * `params` - Fields to update (same options as create_wlan)

  """
  @spec update_wlan(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_wlan(%Client{} = client, site, wlan_id, params) do
    body = normalize_keys(params)
    API.put(client, site_path(client, site, "/rest/wlanconf/#{wlan_id}"), body)
  end

  @doc """
  Enables a wireless network.

  ## Parameters

    * `site` - The site name
    * `wlan_id` - The WLAN `_id`

  """
  @spec enable_wlan(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def enable_wlan(%Client{} = client, site, wlan_id) do
    update_wlan(client, site, wlan_id, %{enabled: true})
  end

  @doc """
  Disables a wireless network.

  ## Parameters

    * `site` - The site name
    * `wlan_id` - The WLAN `_id`

  """
  @spec disable_wlan(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def disable_wlan(%Client{} = client, site, wlan_id) do
    update_wlan(client, site, wlan_id, %{enabled: false})
  end

  @doc """
  Deletes a wireless network.

  ## Parameters

    * `site` - The site name
    * `wlan_id` - The WLAN `_id`

  """
  @spec delete_wlan(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_wlan(%Client{} = client, site, wlan_id) do
    case API.delete(client, site_path(client, site, "/rest/wlanconf/#{wlan_id}")) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Changes the passphrase for a WLAN.

  ## Parameters

    * `site` - The site name
    * `wlan_id` - The WLAN `_id`
    * `passphrase` - The new passphrase

  """
  @spec set_wlan_passphrase(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_wlan_passphrase(%Client{} = client, site, wlan_id, passphrase) do
    update_wlan(client, site, wlan_id, %{x_passphrase: passphrase})
  end

  # ===================
  # Network Operations
  # ===================

  @doc """
  Lists all network configurations (LANs, VLANs, etc.).

  ## Parameters

    * `site` - The site name

  """
  @spec list_networks(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_networks(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/networkconf"))
  end

  @doc """
  Gets a specific network configuration by ID.

  ## Parameters

    * `site` - The site name
    * `network_id` - The network `_id`

  """
  @spec get_network(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_network(%Client{} = client, site, network_id) do
    API.get_one(client, site_path(client, site, "/rest/networkconf/#{network_id}"))
  end

  @doc """
  Creates a new network configuration.

  ## Parameters

    * `site` - The site name
    * `params` - Network configuration
      * `:name` - Required. Network name
      * `:purpose` - Network purpose: "corporate", "guest", "wan", "vlan-only"
      * `:vlan` - VLAN ID
      * `:subnet` - IP subnet (e.g., "192.168.2.1/24")
      * `:dhcpd_enabled` - Enable DHCP server
      * `:dhcpd_start` - DHCP range start
      * `:dhcpd_stop` - DHCP range end
      * `:igmp_snooping` - Enable IGMP snooping
      * `:dhcp_relay_enabled` - Enable DHCP relay

  """
  @spec create_network(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_network(%Client{} = client, site, params) do
    body = normalize_keys(params)

    case API.post(client, site_path(client, site, "/rest/networkconf"), body) do
      {:ok, [network | _]} -> {:ok, network}
      {:ok, network} when is_map(network) -> {:ok, network}
      error -> error
    end
  end

  @doc """
  Updates a network configuration.

  ## Parameters

    * `site` - The site name
    * `network_id` - The network `_id`
    * `params` - Fields to update

  """
  @spec update_network(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_network(%Client{} = client, site, network_id, params) do
    body = normalize_keys(params)
    API.put(client, site_path(client, site, "/rest/networkconf/#{network_id}"), body)
  end

  @doc """
  Deletes a network configuration.

  ## Parameters

    * `site` - The site name
    * `network_id` - The network `_id`

  """
  @spec delete_network(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_network(%Client{} = client, site, network_id) do
    case API.delete(client, site_path(client, site, "/rest/networkconf/#{network_id}")) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # ===================
  # WLAN Groups
  # ===================

  @doc """
  Lists WLAN groups.

  WLAN groups control which APs broadcast which WLANs.

  ## Parameters

    * `site` - The site name

  """
  @spec list_wlan_groups(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_wlan_groups(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/wlangroup"))
  end

  # ===================
  # User Groups
  # ===================

  @doc """
  Lists user groups (bandwidth profiles).

  User groups define bandwidth limits and other policies.

  ## Parameters

    * `site` - The site name

  """
  @spec list_user_groups(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_user_groups(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/usergroup"))
  end

  @doc """
  Creates a user group.

  ## Parameters

    * `site` - The site name
    * `params` - User group configuration
      * `:name` - Required. Group name
      * `:qos_rate_max_down` - Max download rate in Kbps (-1 for unlimited)
      * `:qos_rate_max_up` - Max upload rate in Kbps (-1 for unlimited)

  """
  @spec create_user_group(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_user_group(%Client{} = client, site, params) do
    body = normalize_keys(params)

    case API.post(client, site_path(client, site, "/rest/usergroup"), body) do
      {:ok, [group | _]} -> {:ok, group}
      {:ok, group} when is_map(group) -> {:ok, group}
      error -> error
    end
  end

  @doc """
  Updates a user group.

  ## Parameters

    * `site` - The site name
    * `group_id` - The user group `_id`
    * `params` - Fields to update

  """
  @spec update_user_group(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_user_group(%Client{} = client, site, group_id, params) do
    body = normalize_keys(params)
    API.put(client, site_path(client, site, "/rest/usergroup/#{group_id}"), body)
  end

  @doc """
  Deletes a user group.

  ## Parameters

    * `site` - The site name
    * `group_id` - The user group `_id`

  """
  @spec delete_user_group(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_user_group(%Client{} = client, site, group_id) do
    case API.delete(client, site_path(client, site, "/rest/usergroup/#{group_id}")) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Private helpers

  defp site_path(%Client{} = client, site, path) do
    Client.site_url(client, site, path)
  end

  defp normalize_keys(params) when is_map(params) do
    Map.new(params, fn {k, v} -> {to_string(k), v} end)
  end
end
