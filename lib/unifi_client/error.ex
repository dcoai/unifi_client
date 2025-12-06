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
  def connection_error(reason) do
    new("Connection failed: #{inspect(reason)}", :connection_error, reason)
  end

  @doc """
  Creates an API error from a response body.

  Parses the UniFi API error format and extracts the message and code.
  """
  @spec api_error(map()) :: t()
  def api_error(%{"meta" => %{"msg" => msg, "rc" => rc}}) do
    new(msg, String.to_atom(rc))
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
end

defmodule UnifiClient.NotLoggedInError do
  @moduledoc """
  Error raised when attempting an operation without being logged in.

  This exception is raised when API functions are called with a client
  that has not been authenticated via `UnifiClient.Auth.login/1`.
  """
  defexception message: "Not logged in. Call UnifiClient.Auth.login/1 first."
end
