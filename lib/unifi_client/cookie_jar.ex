defmodule UnifiClient.CookieJar do
  @moduledoc """
  Manages HTTP session cookies and CSRF tokens for UniFi API requests.

  This module is used internally by `UnifiClient.Client` and typically does not
  need to be used directly.

  Uses an Agent to persist cookies across requests, which is necessary
  for maintaining authenticated sessions with the UniFi controller.

  ## Cookie Handling

  The UniFi API uses session-based authentication:
  1. On login, the server returns `Set-Cookie` headers
  2. Subsequent requests must include these cookies

  ## CSRF Token

  The CSRF token is extracted from the `X-Csrf-Token` response header
  and must be sent in the `X-Csrf-Token` header for all POST/PUT/DELETE requests.
  """

  use Agent

  @doc """
  Starts a new cookie jar agent.

  Returns `{:ok, pid}` on success.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    Agent.start_link(fn -> %{cookies: [], csrf_token: nil} end, opts)
  end

  @doc """
  Gets the current cookies from the jar.
  """
  @spec get_cookies(pid()) :: [String.t()]
  def get_cookies(jar) do
    Agent.get(jar, fn state -> state.cookies end)
  end

  @doc """
  Gets the current CSRF token.
  """
  @spec get_csrf_token(pid()) :: String.t() | nil
  def get_csrf_token(jar) do
    Agent.get(jar, fn state -> state.csrf_token end)
  end

  @doc """
  Stores cookies from Set-Cookie headers.
  """
  @spec put_cookies(pid(), [String.t()]) :: :ok
  def put_cookies(jar, cookies) when is_list(cookies) do
    Agent.update(jar, fn state ->
      %{state | cookies: cookies}
    end)
  end

  @doc """
  Stores the CSRF token.
  """
  @spec put_csrf_token(pid(), String.t()) :: :ok
  def put_csrf_token(jar, token) when is_binary(token) do
    Agent.update(jar, fn state ->
      %{state | csrf_token: token}
    end)
  end

  @doc """
  Clears all cookies and the CSRF token.
  """
  @spec clear(pid()) :: :ok
  def clear(jar) do
    Agent.update(jar, fn _state -> %{cookies: [], csrf_token: nil} end)
  end

  @doc """
  Attaches cookie handling to a Req request.

  This adds request and response steps that:
  1. Add stored cookies to outgoing requests
  2. Extract and store cookies from responses
  3. Add CSRF token to modifying requests (POST, PUT, DELETE)
  """
  @spec attach(Req.Request.t(), pid()) :: Req.Request.t()
  def attach(%Req.Request{} = request, jar) do
    request
    |> Req.Request.prepend_request_steps(
      unifi_add_cookies: fn req ->
        add_cookies_step(req, jar)
      end
    )
    |> Req.Request.append_response_steps(
      unifi_save_cookies: fn {req, res} ->
        save_cookies_step({req, res}, jar)
      end
    )
  end

  # Request step: Add cookies and CSRF token
  defp add_cookies_step(req, jar) do
    cookies = get_cookies(jar)
    csrf_token = get_csrf_token(jar)

    req =
      if cookies != [] do
        cookie_header = format_cookies(cookies)
        Req.Request.put_header(req, "cookie", cookie_header)
      else
        req
      end

    # Add CSRF token for modifying requests
    if csrf_token && req.method in [:post, :put, :delete, :patch] do
      Req.Request.put_header(req, "x-csrf-token", csrf_token)
    else
      req
    end
  end

  # Response step: Extract and store cookies and CSRF token
  defp save_cookies_step({req, res}, jar) do
    # Store cookies if present
    case Req.Response.get_header(res, "set-cookie") do
      [] -> :ok
      cookies -> put_cookies(jar, cookies)
    end

    # Store CSRF token from response header if present
    case Req.Response.get_header(res, "x-csrf-token") do
      [token | _] -> put_csrf_token(jar, token)
      [] -> :ok
    end

    {req, res}
  end

  # Format cookies for the Cookie header
  # Takes full Set-Cookie values and extracts just name=value pairs
  defp format_cookies(cookies) do
    cookies
    |> Enum.map(&extract_name_value/1)
    |> Enum.join("; ")
  end

  defp extract_name_value(cookie) do
    cookie
    |> String.split(";")
    |> List.first()
    |> String.trim()
  end
end
