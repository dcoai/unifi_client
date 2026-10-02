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
    * `:rate_limited` - The console is throttling (HTTP 429, or UniFi OS's
      `AUTHENTICATION_FAILED_LIMIT_REACHED` after too many logins);
      `reason.retry_after` is the `Retry-After` header in seconds when sent
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

  # The keys a console error body carries its human-readable message
  # under, in the order they are tried. See message_from_body/1.
  @message_keys ["error", "message", "errors"]

  @type t :: %__MODULE__{
          message: String.t(),
          code: atom() | nil,
          reason: term()
        }

  @doc """
  Creates a new error with the given message and optional code.

  ## Parameters

    * `message` - Human-readable error message. Must be a string: a
      non-binary raises `FunctionClauseError`, so a shape nobody can print
      is stopped where it is made rather than in a caller's record.
    * `code` - Error code atom (e.g., `:not_found`)
    * `reason` - Additional error details

  """
  @spec new(String.t(), atom() | nil, term()) :: t()
  def new(message, code \\ nil, reason \\ nil) when is_binary(message) do
    %__MODULE__{message: message, code: code, reason: reason}
  end

  @doc """
  Creates an authentication error.

  Used when login fails or a session has expired. `reason` carries what
  the console answered (`%{status:, body:}`) when there was an answer.
  """
  @spec authentication_error(String.t(), term()) :: t()
  def authentication_error(message \\ "Authentication failed", reason \\ nil) do
    new(message, :authentication_failed, reason)
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
  Creates a rate-limit error.

  UniFi OS answers `429` after a handful of logins in a few minutes — for
  successful logins too — with the body
  `%{"code" => "AUTHENTICATION_FAILED_LIMIT_REACHED"}`. `retry_after` is the
  `Retry-After` header in seconds, or `nil`.
  """
  @spec rate_limited(term(), non_neg_integer() | nil) :: t()
  def rate_limited(body, retry_after \\ nil) do
    message = message_from_body(body) || "Rate limited by the console"

    new(message, :rate_limited, %{status: 429, body: body, retry_after: retry_after})
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
  def api_error(%{"meta" => %{"msg" => msg, "rc" => rc}}) when is_binary(msg) do
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

  @doc false
  # The human-readable message in a console error body, or nil.
  #
  # Total over terms and always a binary or nil: consoles put the message
  # under `meta.msg` (Network), `error`, `message` or `errors: [first | _]`,
  # and sometimes nest it one level deeper — a Protect export once answered
  # `{"error": {"code": 401, "message": "Unauthorized"}}`. A nested map or
  # list is searched the same way; anything else is nil, so the caller's
  # default message applies.
  @spec message_from_body(term()) :: String.t() | nil
  def message_from_body(%{"meta" => %{"msg" => msg}}) when is_binary(msg), do: msg

  def message_from_body(%{} = body) do
    Enum.find_value(@message_keys, fn key -> body |> Map.get(key) |> message_from_value() end)
  end

  def message_from_body(_), do: nil

  defp message_from_value(msg) when is_binary(msg), do: msg
  defp message_from_value(%{} = nested), do: message_from_body(nested)
  defp message_from_value([first | _]), do: message_from_value(first)
  defp message_from_value(_), do: nil

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
