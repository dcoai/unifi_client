defmodule UnifiClient.API.Devices do
  @moduledoc """
  API operations for UniFi network devices.

  Devices include access points, switches, gateways, and other
  UniFi hardware managed by the controller.

  ## Examples

      {:ok, devices} = UnifiClient.API.Devices.list(client, "default")
      {:ok, device} = UnifiClient.API.Devices.get(client, "default", "aa:bb:cc:dd:ee:ff")
      :ok = UnifiClient.API.Devices.restart(client, "default", "aa:bb:cc:dd:ee:ff")

  """

  alias UnifiClient.{Client, API, Error}

  @doc """
  Lists all devices in a site.

  Returns detailed information about each device including status,
  configuration, and statistics.

  ## Parameters

    * `site` - The site name (e.g., "default")

  ## Returns

      {:ok, [
        %{
          "_id" => "...",
          "mac" => "aa:bb:cc:dd:ee:ff",
          "name" => "Office AP",
          "model" => "U6-Pro",
          "type" => "uap",
          "state" => 1,
          ...
        }
      ]}

  """
  @spec list(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/device"))
  end

  @doc """
  Lists devices with basic information only.

  Returns minimal device data (MAC, type) which is faster for
  large deployments.

  ## Parameters

    * `site` - The site name

  """
  @spec list_basic(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_basic(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/device-basic"))
  end

  @doc """
  Gets detailed information about a specific device.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address (lowercase, colon-separated)

  """
  @spec get(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, site, mac) do
    mac = normalize_mac(mac)

    case list(client, site) do
      {:ok, devices} ->
        case Enum.find(devices, fn d -> d["mac"] == mac end) do
          nil -> {:error, Error.not_found("Device")}
          device -> {:ok, device}
        end

      error ->
        error
    end
  end

  @doc """
  Restarts a device.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address

  """
  @spec restart(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def restart(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => "restart",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Adopts a device into the controller.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address

  """
  @spec adopt(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def adopt(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => "adopt",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Forces re-provisioning of a device.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address

  """
  @spec force_provision(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def force_provision(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => "force-provision",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Upgrades device firmware.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address

  """
  @spec upgrade(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def upgrade(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => "upgrade",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Upgrades device firmware to a specific version.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address
    * `url` - URL of the firmware file

  """
  @spec upgrade_external(Client.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, Error.t()}
  def upgrade_external(%Client{} = client, site, mac, url) do
    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => "upgrade-external",
      "mac" => normalize_mac(mac),
      "url" => url
    })
  end

  @doc """
  Enables or disables the locate feature (blinking LED).

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address
    * `enabled` - `true` to enable, `false` to disable

  """
  @spec locate(Client.t(), String.t(), String.t(), boolean()) :: :ok | {:error, Error.t()}
  def locate(%Client{} = client, site, mac, enabled) do
    cmd = if enabled, do: "set-locate", else: "unset-locate"

    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => cmd,
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Forgets (removes) a device from the controller.

  The device must be offline or disconnected first.

  ## Parameters

    * `site` - The site name
    * `mac` - The device MAC address

  """
  @spec forget(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def forget(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/sitemgr"), %{
      "cmd" => "delete-device",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Sets the name of a device.

  ## Parameters

    * `site` - The site name
    * `device_id` - The device `_id` field
    * `name` - The new name

  """
  @spec set_name(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_name(%Client{} = client, site, device_id, name) do
    API.put(client, site_path(client, site, "/rest/device/#{device_id}"), %{
      "name" => name
    })
  end

  @doc """
  Enables or disables a device port.

  For switches only. Preserves existing port settings (VLAN, speed, etc.).

  ## Parameters

    * `site` - The site name
    * `device_id` - The device `_id` field
    * `port_idx` - The port index (1-based)
    * `enabled` - `true` to enable, `false` to disable

  """
  @spec set_port_enabled(Client.t(), String.t(), String.t(), pos_integer(), boolean()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_port_enabled(%Client{} = client, site, device_id, port_idx, enabled) do
    update_port_overrides(client, site, device_id, [port_idx], %{
      "port_poe_enabled" => enabled
    })
  end

  @doc """
  Sets PoE mode for one or more ports on a switch.

  Preserves existing port settings (VLAN, speed, etc.).

  ## Parameters

    * `site` - The site name
    * `device_id` - The device `_id` field
    * `port_idxs` - List of port indexes (1-based)
    * `poe_mode` - PoE mode: "auto", "off", "pasv24", "passthrough", or "off"

  ## PoE Modes

    * `"auto"` - Automatic PoE (802.3af/at/bt)
    * `"off"` - PoE disabled
    * `"pasv24"` - 24V passive PoE
    * `"passthrough"` - PoE passthrough

  """
  @spec set_poe_mode(Client.t(), String.t(), String.t(), [pos_integer()], String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_poe_mode(%Client{} = client, site, device_id, port_idxs, poe_mode) do
    update_port_overrides(client, site, device_id, port_idxs, %{"poe_mode" => poe_mode})
  end

  @doc """
  Power cycles a PoE port.

  ## Parameters

    * `site` - The site name
    * `mac` - The switch MAC address
    * `port_idx` - The port index (1-based)

  """
  @spec power_cycle_port(Client.t(), String.t(), String.t(), pos_integer()) ::
          :ok | {:error, Error.t()}
  def power_cycle_port(%Client{} = client, site, mac, port_idx) do
    API.command(client, site_path(client, site, "/cmd/devmgr"), %{
      "cmd" => "power-cycle",
      "mac" => normalize_mac(mac),
      "port_idx" => port_idx
    })
  end

  # Private helpers

  defp site_path(%Client{} = client, site, path) do
    Client.site_url(client, site, path)
  end

  defp normalize_mac(mac) do
    mac
    |> String.downcase()
    |> String.replace("-", ":")
  end

  # Updates port_overrides while preserving existing port settings (VLAN, speed, etc.)
  defp update_port_overrides(%Client{} = client, site, device_id, port_idxs, new_settings) do
    # First, get current device configuration
    case API.get(client, site_path(client, site, "/rest/device/#{device_id}")) do
      {:ok, device} ->
        existing_overrides = device["port_overrides"] || []

        # Build updated overrides by merging new settings into existing ones
        updated_overrides =
          Enum.map(port_idxs, fn port_idx ->
            # Find existing override for this port, or create base with just port_idx
            existing =
              Enum.find(existing_overrides, %{"port_idx" => port_idx}, fn override ->
                override["port_idx"] == port_idx
              end)

            # Merge new settings into existing override
            Map.merge(existing, new_settings)
          end)

        # Include unchanged overrides for ports we're not modifying
        unchanged_overrides =
          Enum.reject(existing_overrides, fn override ->
            override["port_idx"] in port_idxs
          end)

        all_overrides = unchanged_overrides ++ updated_overrides

        API.put(client, site_path(client, site, "/rest/device/#{device_id}"), %{
          "port_overrides" => all_overrides
        })

      {:error, _} = error ->
        error
    end
  end
end
