defmodule UnifiClient.Cloud.Client do
  @moduledoc """
  Client for the UniFi Cloud Site Manager API.

  UniFi Cloud provides a centralized way to manage multiple UniFi sites
  through unifi.ui.com and the Site Manager API.

  ## Authentication

  Cloud authentication uses API keys instead of username/password.
  You can generate API keys at unifi.ui.com under your account settings.

  ## Usage

      {:ok, client} = UnifiClient.Cloud.Client.new(api_key: "your-api-key")
      {:ok, hosts} = UnifiClient.Cloud.Sites.list_hosts(client)

  ## API Reference

  The Site Manager API documentation is available at:
  https://developer.ui.com/site-manager-api/

  """

  @base_url "https://api.ui.com"

  @type t :: %__MODULE__{
          api_key: String.t(),
          base_url: String.t(),
          timeout: pos_integer(),
          req: Req.Request.t() | nil
        }

  defstruct [
    :api_key,
    :req,
    base_url: @base_url,
    timeout: 30_000
  ]

  @doc """
  Creates a new UniFi Cloud client.

  ## Options

    * `:api_key` - Required. Your UniFi Cloud API key.
    * `:base_url` - API base URL. Defaults to "https://api.ui.com".
    * `:timeout` - Request timeout in milliseconds. Defaults to 30000.

  ## Returns

    * `{:ok, client}` - Successfully configured client
    * `{:error, reason}` - Configuration error

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    case Keyword.fetch(opts, :api_key) do
      {:ok, api_key} when is_binary(api_key) and api_key != "" ->
        client = %__MODULE__{
          api_key: api_key,
          base_url: Keyword.get(opts, :base_url, @base_url),
          timeout: Keyword.get(opts, :timeout, 30_000)
        }

        {:ok, build_req(client)}

      {:ok, _} ->
        {:error, :invalid_api_key}

      :error ->
        {:error, :api_key_required}
    end
  end

  @doc """
  Creates a new client, raising on error.

  Same as `new/1` but raises `ArgumentError` on invalid configuration.

  ## Example

      client = UnifiClient.Cloud.Client.new!(api_key: "your-api-key")

  """
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, client} -> client
      {:error, reason} -> raise ArgumentError, "Invalid cloud client configuration: #{inspect(reason)}"
    end
  end

  # Private functions

  defp build_req(%__MODULE__{} = client) do
    req =
      Req.new(
        base_url: client.base_url,
        receive_timeout: client.timeout,
        headers: [
          {"x-api-key", client.api_key},
          {"accept", "application/json"},
          {"content-type", "application/json"}
        ]
      )

    %{client | req: req}
  end
end
