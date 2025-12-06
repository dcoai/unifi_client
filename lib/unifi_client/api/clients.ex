defmodule UnifiClient.API.Clients do
  @moduledoc """
  API operations for network clients (stations).

  Clients are devices connected to your UniFi network - computers,
  phones, IoT devices, etc.

  ## Terminology

  - **sta** (station) - Currently connected client
  - **user** - Known/configured client (may or may not be connected)

  ## Examples

      {:ok, clients} = UnifiClient.API.Clients.list_active(client, "default")
      :ok = UnifiClient.API.Clients.block(client, "default", "aa:bb:cc:dd:ee:ff")
      :ok = UnifiClient.API.Clients.reconnect(client, "default", "aa:bb:cc:dd:ee:ff")

  """

  alias UnifiClient.{Client, API, Error}

  @doc """
  Lists all currently connected clients (stations).

  ## Parameters

    * `site` - The site name (e.g., "default")

  ## Returns

      {:ok, [
        %{
          "_id" => "...",
          "mac" => "aa:bb:cc:dd:ee:ff",
          "hostname" => "iPhone",
          "ip" => "192.168.1.100",
          "essid" => "MyNetwork",
          "is_wired" => false,
          "rx_bytes" => 1234567,
          "tx_bytes" => 7654321,
          ...
        }
      ]}

  """
  @spec list_active(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_active(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/sta"))
  end

  @doc """
  Lists all known/configured clients (users).

  This includes clients that have connected in the past but may
  not be currently connected.

  ## Parameters

    * `site` - The site name

  """
  @spec list_known(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_known(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/stat/alluser"))
  end

  @doc """
  Gets information about a specific client by MAC address.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address

  """
  @spec get(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get(%Client{} = client, site, mac) do
    mac = normalize_mac(mac)

    API.get_one(client, site_path(client, site, "/stat/user/#{mac}"))
  end

  @doc """
  Blocks a client from the network.

  Blocked clients cannot connect to any network on this site.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address

  """
  @spec block(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def block(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/stamgr"), %{
      "cmd" => "block-sta",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Unblocks a previously blocked client.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address

  """
  @spec unblock(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def unblock(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/stamgr"), %{
      "cmd" => "unblock-sta",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Forces a client to reconnect.

  Kicks the client off the network, forcing them to reconnect.
  Useful for troubleshooting connection issues.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address

  """
  @spec reconnect(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def reconnect(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/stamgr"), %{
      "cmd" => "kick-sta",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Alias for `reconnect/3`.
  """
  @spec kick(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def kick(client, site, mac), do: reconnect(client, site, mac)

  @doc """
  Authorizes a guest client.

  Used for captive portal / hotspot guest authorization.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address
    * `opts` - Authorization options
      * `:minutes` - Minutes to authorize (default: 60)
      * `:up_bandwidth` - Upload speed limit in Kbps
      * `:down_bandwidth` - Download speed limit in Kbps
      * `:bytes_quota` - Data quota in bytes
      * `:ap_mac` - Specific AP MAC to authorize on

  """
  @spec authorize_guest(Client.t(), String.t(), String.t(), keyword()) ::
          :ok | {:error, Error.t()}
  def authorize_guest(%Client{} = client, site, mac, opts \\ []) do
    minutes = Keyword.get(opts, :minutes, 60)

    body =
      %{
        "cmd" => "authorize-guest",
        "mac" => normalize_mac(mac),
        "minutes" => minutes
      }
      |> maybe_add(:up, opts[:up_bandwidth])
      |> maybe_add(:down, opts[:down_bandwidth])
      |> maybe_add(:bytes, opts[:bytes_quota])
      |> maybe_add(:ap_mac, opts[:ap_mac])

    API.command(client, site_path(client, site, "/cmd/stamgr"), body)
  end

  @doc """
  Unauthorizes (removes authorization from) a guest client.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address

  """
  @spec unauthorize_guest(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def unauthorize_guest(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/stamgr"), %{
      "cmd" => "unauthorize-guest",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Extends guest authorization.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address

  """
  @spec extend_guest(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def extend_guest(%Client{} = client, site, mac) do
    API.command(client, site_path(client, site, "/cmd/hotspot"), %{
      "cmd" => "extend",
      "mac" => normalize_mac(mac)
    })
  end

  @doc """
  Sets a name/alias for a client.

  ## Parameters

    * `site` - The site name
    * `user_id` - The client's `_id` field
    * `name` - The name to set

  """
  @spec set_name(Client.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_name(%Client{} = client, site, user_id, name) do
    API.put(client, site_path(client, site, "/rest/user/#{user_id}"), %{
      "name" => name
    })
  end

  @doc """
  Sets a fixed IP for a client.

  Creates a DHCP reservation for this client.

  ## Parameters

    * `site` - The site name
    * `user_id` - The client's `_id` field
    * `ip` - The IP address to assign
    * `opts` - Options
      * `:network_id` - The network ID to use (required for multiple networks)

  """
  @spec set_fixed_ip(Client.t(), String.t(), String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, Error.t()}
  def set_fixed_ip(%Client{} = client, site, user_id, ip, opts \\ []) do
    body =
      %{
        "use_fixedip" => true,
        "fixed_ip" => ip
      }
      |> maybe_add(:network_id, opts[:network_id])

    API.put(client, site_path(client, site, "/rest/user/#{user_id}"), body)
  end

  @doc """
  Removes a fixed IP assignment from a client.

  ## Parameters

    * `site` - The site name
    * `user_id` - The client's `_id` field

  """
  @spec remove_fixed_ip(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def remove_fixed_ip(%Client{} = client, site, user_id) do
    API.put(client, site_path(client, site, "/rest/user/#{user_id}"), %{
      "use_fixedip" => false
    })
  end

  @doc """
  Forgets a client, removing it from the known clients list.

  ## Parameters

    * `site` - The site name
    * `macs` - A single MAC or list of MAC addresses to forget

  """
  @spec forget(Client.t(), String.t(), String.t() | [String.t()]) :: :ok | {:error, Error.t()}
  def forget(%Client{} = client, site, macs) when is_binary(macs) do
    forget(client, site, [macs])
  end

  def forget(%Client{} = client, site, macs) when is_list(macs) do
    macs = Enum.map(macs, &normalize_mac/1)

    API.command(client, site_path(client, site, "/cmd/stamgr"), %{
      "cmd" => "forget-sta",
      "macs" => macs
    })
  end

  @doc """
  Gets client history/session data.

  ## Parameters

    * `site` - The site name
    * `mac` - The client MAC address
    * `opts` - Options
      * `:start` - Start timestamp (Unix epoch)
      * `:end` - End timestamp (Unix epoch)

  """
  @spec history(Client.t(), String.t(), String.t(), keyword()) ::
          {:ok, [map()]} | {:error, Error.t()}
  def history(%Client{} = client, site, mac, opts \\ []) do
    mac = normalize_mac(mac)

    body =
      %{
        "mac" => mac,
        "type" => "user"
      }
      |> maybe_add(:start, opts[:start])
      |> maybe_add(:end, opts[:end])

    API.post(client, site_path(client, site, "/stat/session"), body)
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

  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, key, value), do: Map.put(map, to_string(key), value)
end
