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

  ## Applications

  A UniFi OS console hosts several applications behind one login. Every
  request function takes an `app:` option selecting which one the path
  belongs to — `:network` (the default) or `:protect`. The application's
  prefix (see `UnifiClient.Client.app_prefix/2`) is prepended to the path.

      {:ok, bootstrap} = UnifiClient.API.get(client, "/api/bootstrap", app: :protect)

  Asking for an application the controller type does not host (Protect on a
  self-hosted `:controller`) returns `{:error, %Error{code: :app_unavailable}}`
  without making a request.

  """

  alias UnifiClient.{Client, Response, Error}

  @doc """
  Makes a GET request to the UniFi API.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path (prefix is added automatically for absolute paths)
    * `opts` - `app:` (default `:network`); everything else is passed to
      `Req.request/2`

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
  Makes a PATCH request to the UniFi API.

  Used for partial updates — the Protect application updates resources
  with PATCH.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path
    * `body` - The request body (will be JSON encoded)
    * `opts` - Additional options passed to `Req.request/2`

  """
  @spec patch(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def patch(%Client{} = client, path, body \\ %{}, opts \\ []) do
    request(:patch, client, path, Keyword.put(opts, :json, body))
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

  @doc """
  Downloads a binary response body (image, video) to a file or into memory.

  The body is streamed rather than buffered, so exports of hundreds of
  megabytes do not have to fit in memory. Only a `200` response is written
  to `dest`; any other status is parsed like every other response and
  returned as `{:error, error}` — the file is never created, and a file left
  half-written by a connection failure mid-stream is removed.

  ## Parameters

    * `client` - An authenticated `UnifiClient.Client`
    * `path` - The API path
    * `dest` - A file path, or `:memory` to return the body as a binary
    * `opts` - `app:` (default `:network`); everything else is passed to
      `Req.request/2`, e.g. `receive_timeout:` for a slow export

  ## Returns

    * `{:ok, dest}` - The file was written (path `dest`)
    * `{:ok, binary}` - The body, when `dest` is `:memory`
    * `{:error, error}` - Request failed or the console returned an error

  """
  @spec download(Client.t(), String.t(), Path.t() | :memory, keyword()) ::
          {:ok, Path.t() | binary()} | {:error, Error.t()}
  def download(%Client{} = client, path, dest, opts \\ []) do
    {app, opts} = Keyword.pop(opts, :app, :network)

    if Client.app_available?(client, app) do
      do_download(client, build_url(client, app, path), dest, opts)
    else
      {:error, Error.app_unavailable(app)}
    end
  end

  # Private functions

  defp request(method, %Client{} = client, path, opts) do
    {app, opts} = Keyword.pop(opts, :app, :network)

    if Client.app_available?(client, app) do
      url = build_url(client, app, path)

      case Req.request(client.req, [{:method, method}, {:url, url} | opts]) do
        {:ok, response} -> Response.parse(response)
        {:error, exception} -> {:error, Error.connection_error(exception)}
      end
    else
      {:error, Error.app_unavailable(app)}
    end
  end

  # Req collects a streamed body into the collectable only on status 200;
  # every other status is collected into a plain binary and decoded like a
  # normal response. That is what keeps error bodies off the disk.
  defp do_download(client, url, :memory, opts) do
    case Req.request(client.req, [{:method, :get}, {:url, url} | opts]) do
      {:ok, %Req.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, response} -> Response.parse(response)
      {:error, exception} -> {:error, Error.connection_error(exception)}
    end
  end

  defp do_download(client, url, dest, opts) when is_binary(dest) do
    req_opts = [{:method, :get}, {:url, url}, {:into, File.stream!(dest)} | opts]

    case Req.request(client.req, req_opts) do
      {:ok, %Req.Response{status: 200}} ->
        {:ok, dest}

      {:ok, response} ->
        Response.parse(response)

      {:error, exception} ->
        # The collectable may have been opened and partially written before
        # the connection dropped; a partial download is not a download.
        _ = File.rm(dest)
        {:error, Error.connection_error(exception)}
    end
  end

  defp build_url(%Client{} = client, app, "/" <> _ = path) do
    # Check if path already has the selected app's prefix to avoid double-prefixing
    prefix = Client.app_prefix(client, app)

    if prefix != "" and String.starts_with?(path, prefix) do
      # Path already has prefix, use as-is
      path
    else
      # Add prefix
      Client.app_url(client, app, path)
    end
  end

  defp build_url(_client, _app, path) do
    # Relative path - use as-is
    path
  end
end
