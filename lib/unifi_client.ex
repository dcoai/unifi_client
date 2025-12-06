defmodule UnifiClient do
  @moduledoc """
  An Elixir client for the UniFi Network Controller API.

  This library provides a comprehensive interface for managing UniFi network
  infrastructure including access points, switches, gateways, and connected clients.

  ## Features

  - **Local Controller Support** - UDM Pro, UniFi OS consoles, and standard controllers
  - **UniFi Cloud Support** - Manage sites via unifi.ui.com with API keys
  - **Real-time Events** - WebSocket integration for live updates
  - **Full API Coverage** - Devices, clients, networks, firewall, statistics

  ## Quick Start

  ### Local Controller (UDM Pro)

      # 1. Create a client
      {:ok, client} = UnifiClient.Client.new(
        host: "192.168.1.1",
        username: "admin",
        password: "secret",
        verify_ssl: false
      )

      # 2. Authenticate
      {:ok, client} = UnifiClient.Auth.login(client)

      # 3. Use the API
      {:ok, devices} = UnifiClient.API.Devices.list(client, "default")
      {:ok, clients} = UnifiClient.API.Clients.list_active(client, "default")

      # 4. Logout when done
      :ok = UnifiClient.Auth.logout(client)

  ### Standard Controller (Self-hosted)

      {:ok, client} = UnifiClient.Client.new(
        host: "192.168.1.100",
        username: "admin",
        password: "secret",
        type: :controller,   # Uses port 8443
        verify_ssl: false
      )

  ### UniFi Cloud

      {:ok, client} = UnifiClient.Cloud.Client.new(api_key: "your-api-key")
      {:ok, hosts} = UnifiClient.Cloud.Sites.list_hosts(client)
      {:ok, devices} = UnifiClient.Cloud.Devices.list(client, host_id, "default")

  ### Real-time Events

      {:ok, ws} = UnifiClient.WebSocket.Client.start_link(
        client: client,
        site: "default",
        subscriber: self()
      )

      # Receive events as messages
      receive do
        {:unifi_event, event} -> IO.inspect(event)
      end

  ## Module Overview

  ### Core Modules

  - `UnifiClient.Client` - Client configuration and connection settings
  - `UnifiClient.Auth` - Authentication (login/logout)
  - `UnifiClient.CookieJar` - Session cookie management (internal)
  - `UnifiClient.Response` - Response parsing (internal)
  - `UnifiClient.Error` - Error types

  ### API Modules

  - `UnifiClient.API.Sites` - Site management and health
  - `UnifiClient.API.Devices` - Device operations (list, restart, adopt, upgrade)
  - `UnifiClient.API.Clients` - Client management (block, authorize, kick)
  - `UnifiClient.API.Networks` - WLAN and network configuration
  - `UnifiClient.API.Firewall` - Firewall rules and port forwarding
  - `UnifiClient.API.Statistics` - Traffic stats and DPI data

  ### Cloud Modules

  - `UnifiClient.Cloud.Client` - Cloud API client with API key auth
  - `UnifiClient.Cloud.Sites` - Cloud host and site management
  - `UnifiClient.Cloud.Devices` - Cloud device queries
  - `UnifiClient.Cloud.Clients` - Cloud client queries

  ### WebSocket Modules

  - `UnifiClient.WebSocket.Client` - Real-time event connection
  - `UnifiClient.WebSocket.Event` - Event parsing and types

  ## Controller Types

  This library supports two controller types:

  | Type | Port | API Prefix | Login Endpoint |
  |------|------|------------|----------------|
  | `:udm_pro` | 443 | `/proxy/network` | `/api/auth/login` |
  | `:controller` | 8443 | (none) | `/api/login` |

  UDM Pro is the default. Use `type: :controller` for self-hosted controllers.

  ## SSL Certificates

  UniFi controllers typically use self-signed certificates. Set `verify_ssl: false`
  to disable certificate verification (development only), or provide a custom
  CA certificate for production use.
  """

  @doc """
  Returns the library version.

  ## Example

      iex> UnifiClient.version()
      "0.1.0"

  """
  @spec version() :: String.t()
  def version, do: "0.1.0"
end
