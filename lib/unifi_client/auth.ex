defmodule UnifiClient.Auth do
  @moduledoc """
  Authentication module for UniFi controllers.

  Handles login and logout operations for local UniFi controllers
  (UDM Pro, UniFi OS, and standard controllers).

  ## Authentication Flow

  1. Call `login/1` with a configured client
  2. The client stores session cookies automatically
  3. Subsequent API calls use the authenticated session
  4. Call `logout/1` when done

  ## Example

      {:ok, client} = UnifiClient.Client.new(
        host: "192.168.1.1",
        username: "admin",
        password: "secret"
      )

      {:ok, client} = UnifiClient.Auth.login(client)

      # Make API calls...

      :ok = UnifiClient.Auth.logout(client)

  """

  alias UnifiClient.{Client, Response, Error}

  @doc """
  Logs in to the UniFi controller.

  Returns an updated client with session cookies and CSRF token stored.

  ## Options

    * `:remember` - Whether to request a persistent session. Defaults to `true`.

  ## Returns

    * `{:ok, client}` - Successfully authenticated client
    * `{:error, error}` - Authentication failed

  """
  @spec login(Client.t(), keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def login(client, opts \\ [])

  def login(%Client{username: nil}, _opts) do
    {:error, Error.authentication_error("Username is required")}
  end

  def login(%Client{password: nil}, _opts) do
    {:error, Error.authentication_error("Password is required")}
  end

  def login(%Client{} = client, opts) do
    remember = Keyword.get(opts, :remember, true)

    body = %{
      "username" => client.username,
      "password" => client.password,
      "remember" => remember
    }

    endpoint = Client.login_endpoint(client)

    case Req.post(client.req, url: endpoint, json: body) do
      {:ok, %Req.Response{status: 200} = response} ->
        handle_login_success(client, response)

      {:ok, %Req.Response{} = response} ->
        {:error, parse_login_error(response)}

      {:error, exception} ->
        {:error, Error.connection_error(exception)}
    end
  end

  @doc """
  Logs out from the UniFi controller.

  Clears the session cookies and invalidates the session on the server.

  ## Returns

    * `:ok` - Successfully logged out
    * `{:error, error}` - Logout failed

  """
  @spec logout(Client.t()) :: :ok | {:error, Error.t()}
  def logout(%Client{logged_in: false}) do
    :ok
  end

  def logout(%Client{} = client) do
    endpoint = Client.logout_endpoint(client)

    case Req.post(client.req, url: endpoint, json: %{}) do
      {:ok, %Req.Response{status: status}} when status in [200, 302] ->
        UnifiClient.CookieJar.clear(client.cookie_jar)
        :ok

      {:ok, %Req.Response{} = response} ->
        case Response.parse_empty(response) do
          :ok ->
            UnifiClient.CookieJar.clear(client.cookie_jar)
            :ok

          error ->
            error
        end

      {:error, exception} ->
        {:error, Error.connection_error(exception)}
    end
  end

  @doc """
  Returns the current user information.

  Requires an authenticated client.

  ## Returns

    * `{:ok, user_info}` - Map containing user information
    * `{:error, error}` - Request failed

  """
  @spec self(Client.t()) :: {:ok, map()} | {:error, Error.t()}
  def self(%Client{} = client) do
    url = Client.api_url(client, "/api/self")

    case Req.get(client.req, url: url) do
      {:ok, response} -> Response.parse_one(response)
      {:error, exception} -> {:error, Error.connection_error(exception)}
    end
  end

  @doc """
  Checks if the client is currently authenticated.

  Makes a request to verify the session is still valid.

  ## Returns

    * `true` - Client is authenticated
    * `false` - Client is not authenticated

  """
  @spec authenticated?(Client.t()) :: boolean()
  def authenticated?(%Client{logged_in: false}), do: false

  def authenticated?(%Client{} = client) do
    case self(client) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Private functions

  defp handle_login_success(client, _response) do
    # Cookies are automatically stored by CookieJar
    # CSRF token is extracted from cookies
    csrf_token = UnifiClient.CookieJar.get_csrf_token(client.cookie_jar)

    client =
      client
      |> Client.put_csrf_token(csrf_token)
      |> Client.mark_logged_in()

    {:ok, client}
  end

  defp parse_login_error(%Req.Response{status: 401, body: body}) do
    msg = extract_error_message(body) || "Invalid username or password"
    Error.authentication_error(msg)
  end

  defp parse_login_error(%Req.Response{status: 403, body: body}) do
    msg = extract_error_message(body) || "Access denied"
    Error.authentication_error(msg)
  end

  defp parse_login_error(%Req.Response{status: status, body: body}) do
    Error.http_error(status, body)
  end

  defp extract_error_message(%{"errors" => [error | _]}), do: error
  defp extract_error_message(%{"error" => error}), do: error
  defp extract_error_message(%{"meta" => %{"msg" => msg}}), do: msg
  defp extract_error_message(_), do: nil
end
