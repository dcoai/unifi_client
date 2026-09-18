defmodule UnifiClient.Protect.API do
  @moduledoc false
  # Request helpers for the Protect application.
  #
  # Every `UnifiClient.Protect.*` module goes through here so `app: :protect`
  # is set in exactly one place. Paths are given relative to the application
  # root (`"/api/cameras"`), and `UnifiClient.API` prepends `/proxy/protect`.

  alias UnifiClient.{API, Client, Error}

  @spec get(Client.t(), String.t(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def get(%Client{} = client, path, opts \\ []) do
    API.get(client, path, Keyword.put(opts, :app, :protect))
  end

  @spec post(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def post(%Client{} = client, path, body, opts \\ []) do
    API.post(client, path, body, Keyword.put(opts, :app, :protect))
  end

  @spec patch(Client.t(), String.t(), map(), keyword()) :: {:ok, term()} | {:error, Error.t()}
  def patch(%Client{} = client, path, body, opts \\ []) do
    API.patch(client, path, body, Keyword.put(opts, :app, :protect))
  end

  @spec download(Client.t(), String.t(), Path.t() | :memory, keyword()) ::
          {:ok, Path.t() | binary()} | {:error, Error.t()}
  def download(%Client{} = client, path, dest, opts \\ []) do
    API.download(client, path, dest, Keyword.put(opts, :app, :protect))
  end

  @doc """
  Appends a query string built from `params`, dropping `nil` values.

  `[]` or all-nil params leave the path untouched, so a request never
  carries a dangling `?`.
  """
  @spec with_query(String.t(), keyword()) :: String.t()
  def with_query(path, params) do
    case Enum.reject(params, fn {_k, v} -> is_nil(v) end) do
      [] -> path
      present -> path <> "?" <> URI.encode_query(present)
    end
  end
end
