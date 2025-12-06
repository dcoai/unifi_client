defmodule UnifiClient.Client do
  @moduledoc """
  The main client struct for connecting to UniFi controllers.

  ## Examples

      # UDM Pro / UniFi OS (port 443, /proxy/network prefix)
      {:ok, client} = UnifiClient.Client.new(
        host: "192.168.1.1",
        username: "admin",
        password: "secret"
      )

      # Standard software controller (port 8443)
      {:ok, client} = UnifiClient.Client.new(
        host: "192.168.1.100",
        username: "admin",
        password: "secret",
        type: :controller
      )

      # With custom SSL options
      {:ok, client} = UnifiClient.Client.new(
        host: "192.168.1.1",
        username: "admin",
        password: "secret",
        verify_ssl: false
      )

  """

  alias UnifiClient.CookieJar

  @type controller_type :: :udm_pro | :controller
  @type t :: %__MODULE__{
          host: String.t(),
          port: pos_integer(),
          username: String.t() | nil,
          password: String.t() | nil,
          type: controller_type(),
          verify_ssl: boolean(),
          timeout: pos_integer(),
          req: Req.Request.t() | nil,
          cookie_jar: pid() | nil,
          csrf_token: String.t() | nil,
          logged_in: boolean()
        }

  defstruct [
    :host,
    :port,
    :username,
    :password,
    :req,
    :cookie_jar,
    :csrf_token,
    type: :udm_pro,
    verify_ssl: false,
    timeout: 30_000,
    logged_in: false
  ]

  @doc """
  Creates a new client configuration.

  ## Options

    * `:host` - Required. The hostname or IP address of the controller.
    * `:username` - The username for authentication.
    * `:password` - The password for authentication.
    * `:type` - The controller type, either `:udm_pro` or `:controller`. Defaults to `:udm_pro`.
    * `:port` - The port number. Defaults to 443 for `:udm_pro` and 8443 for `:controller`.
    * `:verify_ssl` - Whether to verify SSL certificates. Defaults to `false`.
    * `:timeout` - Request timeout in milliseconds. Defaults to 30000.

  ## Returns

    * `{:ok, client}` - A configured client ready for authentication.
    * `{:error, reason}` - If configuration is invalid.

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    with {:ok, host} <- validate_host(opts[:host]),
         {:ok, type} <- validate_type(opts[:type]),
         {:ok, port} <- get_port(opts[:port], type),
         {:ok, cookie_jar} <- CookieJar.start_link() do
      client = %__MODULE__{
        host: host,
        port: port,
        username: opts[:username],
        password: opts[:password],
        type: type,
        verify_ssl: Keyword.get(opts, :verify_ssl, false),
        timeout: Keyword.get(opts, :timeout, 30_000),
        cookie_jar: cookie_jar
      }

      {:ok, build_req(client)}
    end
  end

  @doc """
  Creates a new client, raising on error.

  Same as `new/1` but raises `ArgumentError` on invalid configuration.

  ## Example

      client = UnifiClient.Client.new!(host: "192.168.1.1", username: "admin", password: "secret")

  """
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, client} -> client
      {:error, reason} -> raise ArgumentError, "Invalid client configuration: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the base URL for the controller.

  ## Example

      iex> {:ok, client} = UnifiClient.Client.new(host: "192.168.1.1")
      iex> UnifiClient.Client.base_url(client)
      "https://192.168.1.1:443"

  """
  @spec base_url(t()) :: String.t()
  def base_url(%__MODULE__{host: host, port: port}) do
    "https://#{host}:#{port}"
  end

  @doc """
  Returns the API path prefix based on controller type.

  - UDM Pro: `/proxy/network`
  - Standard controller: empty string
  """
  @spec api_prefix(t()) :: String.t()
  def api_prefix(%__MODULE__{type: :udm_pro}), do: "/proxy/network"
  def api_prefix(%__MODULE__{type: :controller}), do: ""

  @doc """
  Returns the login endpoint for the controller type.
  """
  @spec login_endpoint(t()) :: String.t()
  def login_endpoint(%__MODULE__{type: :udm_pro}), do: "/api/auth/login"
  def login_endpoint(%__MODULE__{type: :controller}), do: "/api/login"

  @doc """
  Returns the logout endpoint for the controller type.
  """
  @spec logout_endpoint(t()) :: String.t()
  def logout_endpoint(%__MODULE__{type: :udm_pro}), do: "/api/auth/logout"
  def logout_endpoint(%__MODULE__{type: :controller}), do: "/api/logout"

  @doc """
  Builds an API URL for a given path.

  Prepends the appropriate API prefix based on controller type.

  ## Example

      iex> {:ok, client} = UnifiClient.Client.new(host: "192.168.1.1", type: :udm_pro)
      iex> UnifiClient.Client.api_url(client, "/api/self")
      "/proxy/network/api/self"

  """
  @spec api_url(t(), String.t()) :: String.t()
  def api_url(%__MODULE__{} = client, path) do
    prefix = api_prefix(client)
    "#{prefix}#{path}"
  end

  @doc """
  Builds a site-specific API URL.

  ## Parameters

    * `client` - The client struct
    * `site` - The site name (e.g., "default")
    * `path` - The API path (e.g., "/stat/device")

  ## Example

      iex> {:ok, client} = UnifiClient.Client.new(host: "192.168.1.1", type: :udm_pro)
      iex> UnifiClient.Client.site_url(client, "default", "/stat/device")
      "/proxy/network/api/s/default/stat/device"

  """
  @spec site_url(t(), String.t(), String.t()) :: String.t()
  def site_url(%__MODULE__{} = client, site, path) do
    api_url(client, "/api/s/#{site}#{path}")
  end

  @doc """
  Updates the client's CSRF token.
  """
  @spec put_csrf_token(t(), String.t() | nil) :: t()
  def put_csrf_token(%__MODULE__{} = client, token) do
    %{client | csrf_token: token}
  end

  @doc """
  Marks the client as logged in.
  """
  @spec mark_logged_in(t()) :: t()
  def mark_logged_in(%__MODULE__{} = client) do
    %{client | logged_in: true}
  end

  @doc """
  Marks the client as logged out.
  """
  @spec mark_logged_out(t()) :: t()
  def mark_logged_out(%__MODULE__{} = client) do
    %{client | logged_in: false, csrf_token: nil}
  end

  # Private functions

  defp validate_host(nil), do: {:error, :host_required}
  defp validate_host(""), do: {:error, :host_required}
  defp validate_host(host) when is_binary(host), do: {:ok, host}
  defp validate_host(_), do: {:error, :invalid_host}

  defp validate_type(nil), do: {:ok, :udm_pro}
  defp validate_type(:udm_pro), do: {:ok, :udm_pro}
  defp validate_type(:controller), do: {:ok, :controller}
  defp validate_type(_), do: {:error, :invalid_type}

  defp get_port(nil, :udm_pro), do: {:ok, 443}
  defp get_port(nil, :controller), do: {:ok, 8443}
  defp get_port(port, _) when is_integer(port) and port > 0, do: {:ok, port}
  defp get_port(_, _), do: {:error, :invalid_port}

  defp build_req(%__MODULE__{} = client) do
    connect_options =
      if client.verify_ssl do
        []
      else
        [transport_opts: [verify: :verify_none]]
      end

    req =
      Req.new(
        base_url: base_url(client),
        receive_timeout: client.timeout,
        connect_options: connect_options
      )
      |> CookieJar.attach(client.cookie_jar)

    %{client | req: req}
  end
end
