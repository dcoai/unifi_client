defmodule UnifiClient.API do
  @moduledoc """
  Base module for UniFi API operations.

  Provides common HTTP request functions used by all API modules.
  This module is primarily used internally by the API submodules
  (`UnifiClient.API.Devices`, `UnifiClient.API.Clients`, etc.).

  ## Direct Usage

  While you can use these functions directly for custom API calls,
  it's recommended to use the higher-level API modules instead:

      # Preferred: Use API submodules
      {:ok, devices} = UnifiClient.API.Devices.list(client, "default")

      # Direct usage for unsupported endpoints
      {:ok, data} = UnifiClient.API.get(client, "/api/s/default/stat/some-endpoint")

  """

  alias UnifiClient.{Client, Response, Error}

  @doc """
  Makes a GET request to the UniFi API.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path (prefix is added automatically for absolute paths)
    * `opts` - Additional options passed to `Req.request/2`

  ## Returns

    * `{:ok, data}` - The parsed response data
    * `{:error, error}` - Request or parsing error

  """
  @spec get(Client.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def get(%Client{} = client, path, opts \\ []) do
    request(:get, client, path, opts)
  end

  @doc """
  Makes a POST request to the UniFi API.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path
    * `body` - The request body (will be JSON encoded)
    * `opts` - Additional options passed to `Req.request/2`

  """
  @spec post(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def post(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(:post, client, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Makes a PUT request to the UniFi API.

  Used for updating existing resources.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path
    * `body` - The request body (will be JSON encoded)
    * `opts` - Additional options passed to `Req.request/2`

  """
  @spec put(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def put(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(:put, client, path, Keyword.put(opts, :json, body))
  end

  @doc """
  Makes a DELETE request to the UniFi API.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path
    * `opts` - Additional options passed to `Req.request/2`

  """
  @spec delete(Client.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def delete(%Client{} = client, path, opts \\ []) do
    request(:delete, client, path, opts)
  end

  @doc """
  Makes a GET request and expects a list of results.

  Wraps single-item responses in a list for consistent handling.

  ## Returns

    * `{:ok, [map()]}` - List of items (may be empty)
    * `{:error, error}` - Request failed

  """
  @spec get_list(Client.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, Error.t()}
  def get_list(client, path, opts \\ []) do
    case get(client, path, opts) do
      {:ok, data} when is_list(data) -> {:ok, data}
      {:ok, data} when is_map(data) -> {:ok, [data]}
      error -> error
    end
  end

  @doc """
  Makes a GET request and expects a single result.

  Returns the first item if multiple are returned, or an error if empty.

  ## Returns

    * `{:ok, map()}` - Single item
    * `{:error, :not_found}` - No items returned

  """
  @spec get_one(Client.t(), String.t(), keyword()) :: {:ok, map()} | {:error, Error.t()}
  def get_one(client, path, opts \\ []) do
    case get(client, path, opts) do
      {:ok, [item | _]} -> {:ok, item}
      {:ok, item} when is_map(item) -> {:ok, item}
      {:ok, []} -> {:error, Error.not_found()}
      error -> error
    end
  end

  @doc """
  Makes a command request (POST that returns minimal data).

  Used for device commands and management operations where the
  response body is not important.

  ## Returns

    * `:ok` - Command succeeded
    * `{:error, error}` - Command failed

  """
  @spec command(Client.t(), String.t(), map()) :: :ok | {:error, Error.t()}
  def command(client, path, body \\ %{}) do
    case post(client, path, body) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  # Private functions

  defp request(method, %Client{} = client, path, opts) do
    url = build_url(client, path)

    case Req.request(client.req, [{:method, method}, {:url, url} | opts]) do
      {:ok, response} -> Response.parse(response)
      {:error, exception} -> {:error, Error.connection_error(exception)}
    end
  end

  defp build_url(%Client{} = client, "/" <> _ = path) do
    # Check if path already has the API prefix to avoid double-prefixing
    prefix = Client.api_prefix(client)

    if prefix != "" and String.starts_with?(path, prefix) do
      # Path already has prefix, use as-is
      path
    else
      # Add prefix
      Client.api_url(client, path)
    end
  end

  defp build_url(_client, path) do
    # Relative path - use as-is
    path
  end
end
