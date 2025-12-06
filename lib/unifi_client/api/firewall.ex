defmodule UnifiClient.API.Firewall do
  @moduledoc """
  API operations for firewall rules.

  Manages firewall rules, port forwarding, and traffic rules
  on UniFi controllers.

  ## Examples

      {:ok, rules} = UnifiClient.API.Firewall.list_rules(client, "default")
      {:ok, forwards} = UnifiClient.API.Firewall.list_port_forwards(client, "default")

  """

  alias UnifiClient.{Client, API, Error}

  # ===================
  # Firewall Rules
  # ===================

  @doc """
  Lists all firewall rules.

  ## Parameters

    * `site` - The site name (e.g., "default")

  """
  @spec list_rules(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_rules(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/firewallrule"))
  end

  @doc """
  Gets a specific firewall rule by ID.

  ## Parameters

    * `site` - The site name
    * `rule_id` - The rule `_id`

  """
  @spec get_rule(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def get_rule(%Client{} = client, site, rule_id) do
    API.get_one(client, site_path(client, site, "/rest/firewallrule/#{rule_id}"))
  end

  @doc """
  Creates a firewall rule.

  ## Parameters

    * `site` - The site name
    * `params` - Rule configuration
      * `:name` - Rule name
      * `:enabled` - Whether the rule is enabled
      * `:action` - "accept", "drop", "reject"
      * `:ruleset` - "WAN_IN", "WAN_OUT", "LAN_IN", "LAN_OUT", etc.
      * `:rule_index` - Order priority (lower = higher priority)
      * `:protocol` - "all", "tcp", "udp", "tcp_udp", "icmp"
      * `:src_address` - Source IP/CIDR or "any"
      * `:dst_address` - Destination IP/CIDR or "any"
      * `:src_port` - Source port(s)
      * `:dst_port` - Destination port(s)
      * `:src_networkconf_id` - Source network ID
      * `:dst_networkconf_id` - Destination network ID

  """
  @spec create_rule(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_rule(%Client{} = client, site, params) do
    body = normalize_keys(params)

    case API.post(client, site_path(client, site, "/rest/firewallrule"), body) do
      {:ok, [rule | _]} -> {:ok, rule}
      {:ok, rule} when is_map(rule) -> {:ok, rule}
      error -> error
    end
  end

  @doc """
  Updates a firewall rule.

  ## Parameters

    * `site` - The site name
    * `rule_id` - The rule `_id`
    * `params` - Fields to update

  """
  @spec update_rule(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_rule(%Client{} = client, site, rule_id, params) do
    body = normalize_keys(params)
    API.put(client, site_path(client, site, "/rest/firewallrule/#{rule_id}"), body)
  end

  @doc """
  Enables a firewall rule.

  ## Parameters

    * `site` - The site name
    * `rule_id` - The rule `_id`

  """
  @spec enable_rule(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def enable_rule(%Client{} = client, site, rule_id) do
    update_rule(client, site, rule_id, %{enabled: true})
  end

  @doc """
  Disables a firewall rule.

  ## Parameters

    * `site` - The site name
    * `rule_id` - The rule `_id`

  """
  @spec disable_rule(Client.t(), String.t(), String.t()) :: {:ok, map()} | {:error, Error.t()}
  def disable_rule(%Client{} = client, site, rule_id) do
    update_rule(client, site, rule_id, %{enabled: false})
  end

  @doc """
  Deletes a firewall rule.

  ## Parameters

    * `site` - The site name
    * `rule_id` - The rule `_id`

  """
  @spec delete_rule(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_rule(%Client{} = client, site, rule_id) do
    case API.delete(client, site_path(client, site, "/rest/firewallrule/#{rule_id}")) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # ===================
  # Port Forwarding
  # ===================

  @doc """
  Lists all port forwarding rules.

  ## Parameters

    * `site` - The site name

  """
  @spec list_port_forwards(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_port_forwards(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/portforward"))
  end

  @doc """
  Gets a specific port forwarding rule by ID.

  ## Parameters

    * `site` - The site name
    * `forward_id` - The port forward `_id`

  """
  @spec get_port_forward(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def get_port_forward(%Client{} = client, site, forward_id) do
    API.get_one(client, site_path(client, site, "/rest/portforward/#{forward_id}"))
  end

  @doc """
  Creates a port forwarding rule.

  ## Parameters

    * `site` - The site name
    * `params` - Port forward configuration
      * `:name` - Rule name
      * `:enabled` - Whether the rule is enabled
      * `:dst_port` - External port(s) to forward (e.g., "80", "8080-8090")
      * `:fwd` - Internal IP address to forward to
      * `:fwd_port` - Internal port (optional, defaults to dst_port)
      * `:proto` - Protocol: "tcp", "udp", "tcp_udp"
      * `:src` - Source IP restriction (optional, "any" for all)
      * `:log` - Enable logging

  ## Example

      UnifiClient.API.Firewall.create_port_forward(client, "default", %{
        name: "Web Server",
        dst_port: "80",
        fwd: "192.168.1.100",
        fwd_port: "8080",
        proto: "tcp"
      })

  """
  @spec create_port_forward(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_port_forward(%Client{} = client, site, params) do
    body =
      params
      |> normalize_keys()
      |> Map.put_new("enabled", true)
      |> Map.put_new("proto", "tcp_udp")

    case API.post(client, site_path(client, site, "/rest/portforward"), body) do
      {:ok, [forward | _]} -> {:ok, forward}
      {:ok, forward} when is_map(forward) -> {:ok, forward}
      error -> error
    end
  end

  @doc """
  Updates a port forwarding rule.

  ## Parameters

    * `site` - The site name
    * `forward_id` - The port forward `_id`
    * `params` - Fields to update

  """
  @spec update_port_forward(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_port_forward(%Client{} = client, site, forward_id, params) do
    body = normalize_keys(params)
    API.put(client, site_path(client, site, "/rest/portforward/#{forward_id}"), body)
  end

  @doc """
  Enables a port forwarding rule.

  ## Parameters

    * `site` - The site name
    * `forward_id` - The port forward `_id`

  """
  @spec enable_port_forward(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def enable_port_forward(%Client{} = client, site, forward_id) do
    update_port_forward(client, site, forward_id, %{enabled: true})
  end

  @doc """
  Disables a port forwarding rule.

  ## Parameters

    * `site` - The site name
    * `forward_id` - The port forward `_id`

  """
  @spec disable_port_forward(Client.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, Error.t()}
  def disable_port_forward(%Client{} = client, site, forward_id) do
    update_port_forward(client, site, forward_id, %{enabled: false})
  end

  @doc """
  Deletes a port forwarding rule.

  ## Parameters

    * `site` - The site name
    * `forward_id` - The port forward `_id`

  """
  @spec delete_port_forward(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_port_forward(%Client{} = client, site, forward_id) do
    case API.delete(client, site_path(client, site, "/rest/portforward/#{forward_id}")) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # ===================
  # Firewall Groups
  # ===================

  @doc """
  Lists all firewall groups.

  Firewall groups are collections of addresses or ports
  that can be referenced in firewall rules.

  ## Parameters

    * `site` - The site name

  """
  @spec list_groups(Client.t(), String.t()) :: {:ok, [map()]} | {:error, Error.t()}
  def list_groups(%Client{} = client, site) do
    API.get_list(client, site_path(client, site, "/rest/firewallgroup"))
  end

  @doc """
  Creates a firewall group.

  ## Parameters

    * `site` - The site name
    * `params` - Group configuration
      * `:name` - Group name
      * `:group_type` - "address-group", "port-group", "ipv6-address-group"
      * `:group_members` - List of members (IPs, CIDRs, or ports)

  """
  @spec create_group(Client.t(), String.t(), map()) :: {:ok, map()} | {:error, Error.t()}
  def create_group(%Client{} = client, site, params) do
    body = normalize_keys(params)

    case API.post(client, site_path(client, site, "/rest/firewallgroup"), body) do
      {:ok, [group | _]} -> {:ok, group}
      {:ok, group} when is_map(group) -> {:ok, group}
      error -> error
    end
  end

  @doc """
  Updates a firewall group.

  ## Parameters

    * `site` - The site name
    * `group_id` - The group `_id`
    * `params` - Fields to update

  """
  @spec update_group(Client.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, Error.t()}
  def update_group(%Client{} = client, site, group_id, params) do
    body = normalize_keys(params)
    API.put(client, site_path(client, site, "/rest/firewallgroup/#{group_id}"), body)
  end

  @doc """
  Deletes a firewall group.

  ## Parameters

    * `site` - The site name
    * `group_id` - The group `_id`

  """
  @spec delete_group(Client.t(), String.t(), String.t()) :: :ok | {:error, Error.t()}
  def delete_group(%Client{} = client, site, group_id) do
    case API.delete(client, site_path(client, site, "/rest/firewallgroup/#{group_id}")) do
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
