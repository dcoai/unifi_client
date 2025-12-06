defmodule UnifiClient.WebSocket.Event do
  @moduledoc """
  Event parsing and type definitions for UniFi WebSocket events.

  ## Event Types

  UniFi WebSocket events include:

  ### Client Events (sta:sync, EVT_WU_*, EVT_LU_*)
  - `EVT_WU_Connected` - Wireless user connected
  - `EVT_WU_Disconnected` - Wireless user disconnected
  - `EVT_WU_Roam` - Wireless user roamed to another AP
  - `EVT_LU_Connected` - LAN user connected
  - `EVT_LU_Disconnected` - LAN user disconnected

  ### Device Events (device:sync, EVT_AP_*, EVT_SW_*, EVT_GW_*)
  - `EVT_AP_Connected` - Access point connected
  - `EVT_AP_Disconnected` - Access point disconnected
  - `EVT_AP_Restarted` - Access point restarted
  - `EVT_AP_Upgraded` - Access point firmware upgraded
  - `EVT_SW_Connected` - Switch connected
  - `EVT_SW_Disconnected` - Switch disconnected
  - `EVT_GW_Connected` - Gateway connected
  - `EVT_GW_WANTransition` - WAN failover event

  ### System Events
  - `EVT_AD_Login` - Admin login
  - `EVT_AD_Logout` - Admin logout

  """

  @type event_type ::
          :client_connected
          | :client_disconnected
          | :client_roam
          | :device_connected
          | :device_disconnected
          | :device_restarted
          | :device_upgraded
          | :wan_transition
          | :admin_login
          | :admin_logout
          | :sync
          | :unknown

  @type t :: %{
          type: event_type(),
          key: String.t() | nil,
          message: String.t() | nil,
          time: DateTime.t() | nil,
          data: map(),
          raw: map()
        }

  @doc """
  Parses a raw WebSocket event into a structured format.

  ## Examples

      iex> UnifiClient.WebSocket.Event.parse(%{"data" => [%{"key" => "EVT_WU_Connected"}]})
      %{type: :client_connected, key: "EVT_WU_Connected", ...}

  """
  @spec parse(map()) :: t() | [t()]
  def parse(%{"data" => events}) when is_list(events) do
    Enum.map(events, &parse_single/1)
  end

  def parse(%{"data" => event}) when is_map(event) do
    parse_single(event)
  end

  def parse(event) when is_map(event) do
    parse_single(event)
  end

  @doc """
  Returns the event type as an atom.
  """
  @spec type(map()) :: event_type()
  def type(%{"key" => key}) do
    classify_event(key)
  end

  def type(_), do: :unknown

  @doc """
  Checks if an event is a client-related event.
  """
  @spec client_event?(t() | map()) :: boolean()
  def client_event?(%{type: type}) do
    type in [:client_connected, :client_disconnected, :client_roam]
  end

  def client_event?(%{"key" => key}) do
    String.starts_with?(key, "EVT_WU_") or
      String.starts_with?(key, "EVT_LU_") or
      key == "sta:sync"
  end

  def client_event?(_), do: false

  @doc """
  Checks if an event is a device-related event.
  """
  @spec device_event?(t() | map()) :: boolean()
  def device_event?(%{type: type}) do
    type in [:device_connected, :device_disconnected, :device_restarted, :device_upgraded]
  end

  def device_event?(%{"key" => key}) do
    String.starts_with?(key, "EVT_AP_") or
      String.starts_with?(key, "EVT_SW_") or
      String.starts_with?(key, "EVT_GW_") or
      key == "device:sync"
  end

  def device_event?(_), do: false

  @doc """
  Extracts the MAC address from an event, if present.
  """
  @spec extract_mac(map()) :: String.t() | nil
  def extract_mac(%{"user" => mac}) when is_binary(mac), do: mac
  def extract_mac(%{"mac" => mac}) when is_binary(mac), do: mac
  def extract_mac(%{"client" => mac}) when is_binary(mac), do: mac
  def extract_mac(%{"ap" => mac}) when is_binary(mac), do: mac
  def extract_mac(%{"sw" => mac}) when is_binary(mac), do: mac
  def extract_mac(%{"gw" => mac}) when is_binary(mac), do: mac
  def extract_mac(_), do: nil

  @doc """
  Extracts the timestamp from an event as a DateTime.
  """
  @spec extract_time(map()) :: DateTime.t() | nil
  def extract_time(%{"time" => time}) when is_integer(time) do
    # UniFi timestamps are in milliseconds
    case DateTime.from_unix(div(time, 1000)) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  def extract_time(%{"datetime" => dt_string}) when is_binary(dt_string) do
    case DateTime.from_iso8601(dt_string) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  def extract_time(_), do: nil

  # Private functions

  defp parse_single(event) do
    %{
      type: type(event),
      key: event["key"],
      message: event["msg"],
      time: extract_time(event),
      data: Map.drop(event, ["key", "msg", "time", "datetime"]),
      raw: event
    }
  end

  defp classify_event("EVT_WU_Connected"), do: :client_connected
  defp classify_event("EVT_WU_Disconnected"), do: :client_disconnected
  defp classify_event("EVT_WU_Roam"), do: :client_roam
  defp classify_event("EVT_WU_RoamRadio"), do: :client_roam
  defp classify_event("EVT_LU_Connected"), do: :client_connected
  defp classify_event("EVT_LU_Disconnected"), do: :client_disconnected

  defp classify_event("EVT_AP_Connected"), do: :device_connected
  defp classify_event("EVT_AP_Disconnected"), do: :device_disconnected
  defp classify_event("EVT_AP_Restarted"), do: :device_restarted
  defp classify_event("EVT_AP_Upgraded"), do: :device_upgraded
  defp classify_event("EVT_AP_Lost_Contact"), do: :device_disconnected
  defp classify_event("EVT_AP_Adopted"), do: :device_connected

  defp classify_event("EVT_SW_Connected"), do: :device_connected
  defp classify_event("EVT_SW_Disconnected"), do: :device_disconnected
  defp classify_event("EVT_SW_Restarted"), do: :device_restarted
  defp classify_event("EVT_SW_Upgraded"), do: :device_upgraded
  defp classify_event("EVT_SW_Lost_Contact"), do: :device_disconnected
  defp classify_event("EVT_SW_Adopted"), do: :device_connected

  defp classify_event("EVT_GW_Connected"), do: :device_connected
  defp classify_event("EVT_GW_Disconnected"), do: :device_disconnected
  defp classify_event("EVT_GW_Restarted"), do: :device_restarted
  defp classify_event("EVT_GW_WANTransition"), do: :wan_transition
  defp classify_event("EVT_GW_Lost_Contact"), do: :device_disconnected

  defp classify_event("EVT_AD_Login"), do: :admin_login
  defp classify_event("EVT_AD_Logout"), do: :admin_logout

  defp classify_event("sta:sync"), do: :sync
  defp classify_event("device:sync"), do: :sync
  defp classify_event("user:sync"), do: :sync
  defp classify_event("speed-test:update"), do: :sync

  defp classify_event(_), do: :unknown
end
