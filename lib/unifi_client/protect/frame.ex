defmodule UnifiClient.Protect.Frame do
  @moduledoc """
  Decoder for the binary packets on Protect's update WebSocket.

  Protect does not send JSON text frames. Each WebSocket message carries
  one or more **packets**, each an 8-byte header followed by a payload:

      <<type::8, format::8, deflated::8, _reserved::8, size::32-big, payload::binary-size(size)>>

  | field      | values                                              |
  |------------|-----------------------------------------------------|
  | `type`     | 1 action, 2 payload                                 |
  | `format`   | 1 JSON, 2 UTF-8 string, 3 raw buffer                |
  | `deflated` | 1 if the payload is zlib-compressed                 |

  A logical **message** is an action packet (`%{"action" => "add" | "update"
  | "remove", "modelKey" => ..., "id" => ..., "newUpdateId" => ...}`)
  immediately followed by its payload packet — the changed fields for
  `update`, the whole object for `add`.

  Both `decode/1` and `decode_message/1` are total over binaries: malformed
  input is an `{:error, reason}` value, never an exception. Incompleteness
  (`:incomplete_header`, `{:incomplete_payload, needed, have}`) is
  distinguished from corruption so a streaming caller can wait for more
  bytes in the first case and discard in the second.
  """

  defstruct [:type, :format, :payload]

  @type packet_type :: :action | :payload | {:unknown, non_neg_integer()}
  @type format :: :json | :utf8 | :buffer | {:unknown, non_neg_integer()}
  @type t :: %__MODULE__{type: packet_type(), format: format(), payload: term()}

  @type incomplete ::
          :incomplete_header | {:incomplete_payload, non_neg_integer(), non_neg_integer()}
  @type reason ::
          incomplete()
          | :bad_deflate
          | {:invalid_json, term()}
          | {:unexpected_sequence, term()}

  @type message :: %{action: map(), data: term()}

  @header_size 8

  @doc """
  Decodes one packet from the front of `binary`.

  Returns the packet and the unconsumed remainder.
  """
  @spec decode(binary()) :: {:ok, t(), binary()} | {:error, reason()}
  def decode(<<type::8, format::8, deflated::8, _::8, size::32-big, rest::binary>>) do
    case rest do
      <<raw::binary-size(^size), remainder::binary>> ->
        with {:ok, bytes} <- inflate(deflated, raw),
             {:ok, payload} <- parse_payload(format_of(format), bytes) do
          {:ok, %__MODULE__{type: type_of(type), format: format_of(format), payload: payload},
           remainder}
        end

      _ ->
        {:error, {:incomplete_payload, size, byte_size(rest)}}
    end
  end

  def decode(binary) when is_binary(binary) and byte_size(binary) < @header_size do
    {:error, :incomplete_header}
  end

  @doc """
  Decodes one action packet and its payload packet from the front of
  `binary`.

  Returns `%{action: map, data: term}` and the unconsumed remainder. The
  first packet must be an `:action` carrying JSON and the second a
  `:payload`; any other pairing is `{:error, {:unexpected_sequence, _}}`.
  """
  @spec decode_message(binary()) :: {:ok, message(), binary()} | {:error, reason()}
  def decode_message(binary) when is_binary(binary) do
    with {:ok, first, rest} <- decode(binary),
         :ok <- expect(first, :action, :json),
         {:ok, second, rest} <- decode(rest),
         :ok <- expect(second, :payload, nil) do
      {:ok, %{action: first.payload, data: second.payload}, rest}
    end
  end

  # Private functions

  defp type_of(1), do: :action
  defp type_of(2), do: :payload
  defp type_of(n), do: {:unknown, n}

  defp format_of(1), do: :json
  defp format_of(2), do: :utf8
  defp format_of(3), do: :buffer
  defp format_of(n), do: {:unknown, n}

  defp inflate(1, raw), do: safe_uncompress(raw)
  defp inflate(_, raw), do: {:ok, raw}

  defp parse_payload(:json, bytes) do
    case Jason.decode(bytes) do
      {:ok, term} -> {:ok, term}
      {:error, reason} -> {:error, {:invalid_json, reason}}
    end
  end

  defp parse_payload(_, bytes), do: {:ok, bytes}

  defp expect(%__MODULE__{type: type}, type, nil), do: :ok
  defp expect(%__MODULE__{type: type, format: format}, type, format), do: :ok

  defp expect(%__MODULE__{type: type, format: format}, want_type, want_format) do
    {:error, {:unexpected_sequence, %{got: {type, format}, want: {want_type, want_format}}}}
  end

  # Every Erlang zlib inflate function raises on corrupt data; there is no
  # error-returning variant. Running it in a throwaway monitored process
  # turns that exception into a value without rescuing anything in the
  # caller: a result message means success, a :DOWN means the data was bad.
  defp safe_uncompress(raw) do
    parent = self()
    ref = make_ref()

    {pid, monitor} =
      spawn_monitor(fn -> send(parent, {ref, :zlib.uncompress(raw)}) end)

    receive do
      {^ref, bytes} ->
        Process.demonitor(monitor, [:flush])
        {:ok, bytes}

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        {:error, :bad_deflate}
    end
  end
end
