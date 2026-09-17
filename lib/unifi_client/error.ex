defmodule UnifiClient.Error do
  @moduledoc """
  Error types for UniFi API operations.

  This module defines the error struct returned by API operations
  when something goes wrong.

  ## Error Codes

  Common error codes include:

    * `:authentication_failed` - Login failed or session expired
    * `:not_found` - Resource does not exist
    * `:connection_error` - Network or connection issue
    * `:http_error` - HTTP error response (4xx, 5xx)
    * `:timeout` - The console did not answer within the request timeout
    * `:app_unavailable` - The controller type does not host the requested
      application (e.g. Protect on a self-hosted Network controller)
    * `:error` - Generic API error from controller

  ## Error Handling

      case UnifiClient.API.Devices.list(client, "default") do
        {:ok, devices} ->
          # Success
          devices

        {:error, %UnifiClient.Error{code: :authentication_failed}} ->
          # Re-authenticate
          {:ok, client} = UnifiClient.Auth.login(client)
          UnifiClient.API.Devices.list(client, "default")

        {:error, %UnifiClient.Error{code: :not_found}} ->
          # Site doesn't exist
          []

        {:error, error} ->
          # Other error
          Logger.error("API error: \#{error.message}")
          {:error, error}
      end

  """

  defexception [:message, :code, :reason]

  @type t :: %__MODULE__{
          message: String.t(),
          code: atom() | nil,
          reason: term()
        }

  @doc """
  Creates a new error with the given message and optional code.

  ## Parameters

    * `message` - Human-readable error message
    * `code` - Error code atom (e.g., `:not_found`)
    * `reason` - Additional error details

  """
  @spec new(String.t(), atom() | nil, term()) :: t()
  def new(message, code \\ nil, reason \\ nil) do
    %__MODULE__{message: message, code: code, reason: reason}
  end

  @doc """
  Creates an authentication error.

  Used when login fails or a session has expired.
  """
  @spec authentication_error(String.t()) :: t()
  def authentication_error(message \\ "Authentication failed") do
    new(message, :authentication_failed)
  end

  @doc """
  Creates a not found error.

  Used when a requested resource (device, client, site) doesn't exist.
  """
  @spec not_found(String.t()) :: t()
  def not_found(resource \\ "Resource") do
    new("#{resource} not found", :not_found)
  end

  @doc """
  Creates a connection error.

  Used when the connection to the controller fails (network issues,
  DNS resolution, SSL errors, etc.).
  """
  @spec connection_error(term()) :: t()
  def connection_error(%Req.TransportError{reason: :timeout} = reason) do
    new("Request timed out", :timeout, reason)
  end

  def connection_error(reason) do
    new("Connection failed: #{inspect(reason)}", :connection_error, reason)
  end

  @doc """
  Creates an error for an application the controller type does not host.

  Protect exists only on UniFi OS consoles (`type: :udm_pro`); asking a
  `:controller` client for it fails before any request is made.
  """
  @spec app_unavailable(atom()) :: t()
  def app_unavailable(app) do
    new("Application #{app} is not available on this controller type", :app_unavailable, app)
  end

  @doc """
  Creates an API error from a response body.

  Understands both console error formats:

    * Network: `%{"meta" => %{"rc" => "error", "msg" => msg}}` — the code is
      the `rc` value as an atom.
    * Protect: `%{"error" => msg, "name" => name, "statusCode" => status}` —
      the code follows the status (`:authentication_failed` for 401/403,
      `:not_found` for 404, `:http_error` otherwise) so callers can match on
      the same codes for either application; `reason` keeps `status` and
      `name`.
  """
  @spec api_error(map()) :: t()
  def api_error(%{"meta" => %{"msg" => msg, "rc" => rc}}) do
    new(msg, String.to_atom(rc))
  end

  def api_error(%{"error" => msg, "name" => name, "statusCode" => status})
      when is_binary(msg) and is_integer(status) do
    new(msg, code_for_status(status), %{status: status, name: name})
  end

  def api_error(%{"meta" => %{"rc" => rc}}) do
    new("API error: #{rc}", String.to_atom(rc))
  end

  def api_error(response) do
    new("Unknown API error", :unknown, response)
  end

  @doc """
  Creates an HTTP error from a status code.

  Maps common HTTP status codes to user-friendly messages.
  """
  @spec http_error(integer(), term()) :: t()
  def http_error(status, body \\ nil) do
    message =
      case status do
        400 -> "Bad request"
        401 -> "Unauthorized - check credentials"
        403 -> "Forbidden - insufficient permissions"
        404 -> "Not found"
        500 -> "Internal server error"
        502 -> "Bad gateway"
        503 -> "Service unavailable"
        _ -> "HTTP error #{status}"
      end

    new(message, :http_error, %{status: status, body: body})
  end

  @impl true
  def message(%__MODULE__{message: message}), do: message

  defp code_for_status(status) when status in [401, 403], do: :authentication_failed
  defp code_for_status(404), do: :not_found
  defp code_for_status(_), do: :http_error
end

defmodule UnifiClient.NotLoggedInError do
  @moduledoc """
  Error raised when attempting an operation without being logged in.

  This exception is raised when API functions are called with a client
  that has not been authenticated via `UnifiClient.Auth.login/1`.
  """
  defexception message: "Not logged in. Call UnifiClient.Auth.login/1 first."
end
