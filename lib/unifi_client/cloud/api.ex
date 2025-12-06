defmodule UnifiClient.Cloud.API do
  @moduledoc """
  Base module for UniFi Cloud API operations.

  Provides common HTTP request functions used by the Cloud API modules.
  This module is primarily for internal use by `UnifiClient.Cloud.Sites`,
  `UnifiClient.Cloud.Devices`, and `UnifiClient.Cloud.Clients`.
  """

  alias UnifiClient.Cloud.Client
  alias UnifiClient.Error

  @doc """
  Makes a GET request to the UniFi Cloud API.
  """
  @spec get(Client.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def get(%Client{} = client, path, opts \\ []) do
    request(:get, client, path, opts)
  end

  @doc """
  Makes a POST request to the UniFi Cloud API.
  """
  @spec post(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def post(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(:post, client, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Makes a PUT request to the UniFi Cloud API.
  """
  @spec put(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def put(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(:put, client, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Makes a DELETE request to the UniFi Cloud API.
  """
  @spec delete(Client.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def delete(%Client{} = client, path, opts \\ []) do
    request(:delete, client, path, opts)
  end

  # Private functions

  defp request(method, %Client{} = client, path, opts) do
    case Req.request(client.req, [{:method, method}, {:url, path} | opts]) do
      {:ok, response} -> parse_cloud_response(response)
      {:error, exception} -> {:error, Error.connection_error(exception)}
    end
  end

  # Cloud API responses have a different format than local controller
  defp parse_cloud_response(%Req.Response{status: status, body: body}) when status in 200..299 do
    parse_cloud_body(body)
  end

  defp parse_cloud_response(%Req.Response{status: 401}) do
    {:error, Error.authentication_error("Invalid API key")}
  end

  defp parse_cloud_response(%Req.Response{status: 403}) do
    {:error, Error.authentication_error("Access denied")}
  end

  defp parse_cloud_response(%Req.Response{status: 404}) do
    {:error, Error.not_found()}
  end

  defp parse_cloud_response(%Req.Response{status: status, body: body}) do
    {:error, Error.http_error(status, body)}
  end

  # Cloud API may return data directly without meta wrapper
  defp parse_cloud_body(%{"data" => data}) when is_list(data), do: {:ok, data}
  defp parse_cloud_body(%{"data" => data}) when is_map(data), do: {:ok, data}
  defp parse_cloud_body(data) when is_list(data), do: {:ok, data}
  defp parse_cloud_body(data) when is_map(data), do: {:ok, data}
  defp parse_cloud_body(nil), do: {:ok, nil}
end
