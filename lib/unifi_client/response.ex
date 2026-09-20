defmodule UnifiClient.Response do
  @moduledoc """
  Handles parsing and normalizing UniFi API responses.

  This module is used internally by `UnifiClient.API` and typically does not
  need to be used directly.

  ## Response Format

  UniFi API responses follow this format:

      {
        "meta": {
          "rc": "ok",
          "msg": "optional message"
        },
        "data": [...]
      }

  Where `rc` is the result code:
  - `"ok"` - Success
  - `"error"` - Error with message in `msg`

  Protect responses have no envelope: a success body is the bare JSON
  resource and an error body is

      {
        "error": "message",
        "name": "NotFound",
        "statusCode": 404
      }

  which is recognised on any HTTP status and always yields `{:error, _}`.

  """

  alias UnifiClient.Error

  @type result :: {:ok, term()} | {:error, Error.t()}

  @doc """
  Parses a Req response and extracts the data.

  Returns `{:ok, data}` on success or `{:error, error}` on failure.
  """
  @spec parse(Req.Response.t()) :: result()
  def parse(%Req.Response{body: %{"error" => msg, "name" => _, "statusCode" => code} = body})
      when is_binary(msg) and is_integer(code) do
    {:error, Error.api_error(body)}
  end

  def parse(%Req.Response{status: 429, body: body} = response) do
    {:error, Error.rate_limited(body, retry_after(response))}
  end

  def parse(
        %Req.Response{body: %{"code" => "AUTHENTICATION_FAILED_LIMIT_REACHED"} = body} = response
      ) do
    {:error, Error.rate_limited(body, retry_after(response))}
  end

  def parse(%Req.Response{status: status, body: body}) when status in 200..299 do
    parse_body(body)
  end

  def parse(%Req.Response{status: 401, body: body}) do
    {:error, Error.authentication_error(extract_message(body))}
  end

  def parse(%Req.Response{status: 404}) do
    {:error, Error.not_found()}
  end

  def parse(%Req.Response{status: status, body: body}) do
    {:error, Error.http_error(status, body)}
  end

  @doc """
  Parses a response and extracts a single item from data.

  Useful for endpoints that return a single resource.
  """
  @spec parse_one(Req.Response.t()) :: result()
  def parse_one(response) do
    case parse(response) do
      {:ok, [item]} -> {:ok, item}
      {:ok, [item | _]} -> {:ok, item}
      {:ok, []} -> {:error, Error.not_found()}
      {:ok, data} when is_map(data) -> {:ok, data}
      error -> error
    end
  end

  @doc """
  Parses a response expecting no data (e.g., commands).
  """
  @spec parse_empty(Req.Response.t()) :: :ok | {:error, Error.t()}
  def parse_empty(response) do
    case parse(response) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Private functions

  defp parse_body(%{"meta" => %{"rc" => "ok"}, "data" => data}) do
    {:ok, data}
  end

  defp parse_body(%{"meta" => %{"rc" => "ok"}} = body) do
    # Some endpoints return data at root level
    {:ok, Map.drop(body, ["meta"])}
  end

  defp parse_body(%{"meta" => %{"rc" => "error"}} = body) do
    {:error, Error.api_error(body)}
  end

  defp parse_body(%{"meta" => _} = body) do
    {:error, Error.api_error(body)}
  end

  # Handle responses without meta wrapper
  defp parse_body(body) when is_map(body) do
    {:ok, body}
  end

  defp parse_body(body) when is_list(body) do
    {:ok, body}
  end

  defp parse_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> parse_body(decoded)
      {:error, _} -> {:ok, body}
    end
  end

  defp parse_body(nil) do
    {:ok, nil}
  end

  @doc false
  def retry_after(%Req.Response{} = response) do
    case Req.Response.get_header(response, "retry-after") do
      [value | _] ->
        case Integer.parse(value) do
          {seconds, _} when seconds >= 0 -> seconds
          _ -> nil
        end

      [] ->
        nil
    end
  end

  defp extract_message(%{"meta" => %{"msg" => msg}}), do: msg
  defp extract_message(%{"error" => msg}), do: msg
  defp extract_message(%{"message" => msg}), do: msg
  defp extract_message(_), do: nil
end
