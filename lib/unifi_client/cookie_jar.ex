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
    Agent.start_link(&initial_state/0, opts)
  end

  defp initial_state, do: %{cookies: [], csrf_token: nil, generation: 0, renewal: nil}

  @doc """
  The session generation: incremented by every successful `renew/3`.

  A caller records it before a request; if the request fails with a 401 and
  the generation has moved on, someone else already renewed the session and
  the caller only needs to retry.
  """
  @spec generation(pid()) :: non_neg_integer()
  def generation(jar), do: Agent.get(jar, & &1.generation)

  @doc """
  Renews the session at most once per expiry, however many callers ask.

  `seen` is the generation the caller observed before its failed request.
  If the jar has moved past it, `{:ok, :already_renewed}` — retry with the
  cookies already in the jar. Otherwise the first caller becomes the owner
  and runs `login_fun` **in its own process** (the request steps talk to
  this agent, so the login cannot run inside it), then releases: a success
  bumps the generation and every waiter gets `{:ok, :renewed}`; a failure
  is returned to the owner and every waiter, and the generation is
  unchanged. Waiters monitor the owner; if it dies mid-login the next one
  takes the lock.

  UniFi OS rate-limits logins (HTTP 429 after a handful in a few minutes),
  which is why N concurrent callers must produce one login, not N.
  """
  @spec renew(pid(), non_neg_integer(), (-> {:ok, term()} | {:error, term()})) ::
          {:ok, :renewed | :already_renewed} | {:error, term()}
  def renew(jar, seen, login_fun) when is_function(login_fun, 0) do
    me = self()
    ref = make_ref()

    decision =
      Agent.get_and_update(jar, fn
        %{generation: gen} = state when gen > seen ->
          {:already_renewed, state}

        %{renewal: nil} = state ->
          {:owner, %{state | renewal: %{owner: me, waiters: []}}}

        %{renewal: %{owner: owner, waiters: waiters} = renewal} = state ->
          {{:wait, owner}, %{state | renewal: %{renewal | waiters: [{me, ref} | waiters]}}}
      end)

    case decision do
      :already_renewed ->
        {:ok, :already_renewed}

      :owner ->
        result = login_fun.()
        release(jar, result)

        case result do
          {:ok, _} -> {:ok, :renewed}
          {:error, _} = error -> error
        end

      {:wait, owner} ->
        monitor = Process.monitor(owner)

        receive do
          {:renewal, ^ref, result} ->
            Process.demonitor(monitor, [:flush])
            result

          {:DOWN, ^monitor, :process, ^owner, _reason} ->
            # The owner died before releasing; the lock is cleared below by
            # whoever notices first, then we compete again.
            Agent.update(jar, fn
              %{renewal: %{owner: ^owner}} = state -> %{state | renewal: nil}
              state -> state
            end)

            renew(jar, seen, login_fun)
        end
    end
  end

  defp release(jar, result) do
    waiters =
      Agent.get_and_update(jar, fn %{renewal: %{waiters: waiters}} = state ->
        state =
          case result do
            {:ok, _} -> %{state | generation: state.generation + 1, renewal: nil}
            {:error, _} -> %{state | renewal: nil}
          end

        {waiters, state}
      end)

    reply =
      case result do
        {:ok, _} -> {:ok, :renewed}
        {:error, _} = error -> error
      end

    Enum.each(waiters, fn {pid, ref} -> send(pid, {:renewal, ref, reply}) end)
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
  Stores cookies from Set-Cookie headers, deriving the CSRF token from them
  when they carry one.

  Consoles deliver the token two ways, and the header (see `attach/2`) is
  not always present:

    * self-hosted Network controller (`/api/login`): a `csrf_token=` cookie
      whose value *is* the token;
    * UniFi OS (`/api/auth/login`): a `TOKEN=` cookie holding a JWT whose
      payload has a `csrfToken` claim.

  Whatever is found here is stored; an `x-csrf-token` response header
  processed in the same response step overrides it, since the header is
  the console's most explicit statement. Cookies without either yield no
  token and leave the stored one alone.
  """
  @spec put_cookies(pid(), [String.t()]) :: :ok
  def put_cookies(jar, cookies) when is_list(cookies) do
    derived = csrf_from_cookies(cookies)

    Agent.update(jar, fn state ->
      %{state | cookies: cookies, csrf_token: derived || state.csrf_token}
    end)
  end

  @doc false
  def csrf_from_cookies(cookies) do
    Enum.find_value(cookies, fn cookie ->
      case cookie
           |> String.split(";")
           |> List.first()
           |> String.trim()
           |> String.split("=", parts: 2) do
        ["csrf_token", value] when value != "" -> value
        ["TOKEN", jwt] -> csrf_claim(jwt)
        _ -> nil
      end
    end)
  end

  # The csrfToken claim of a JWT, or nil for anything that is not one.
  # Every step returns a value on bad input; nothing here raises.
  defp csrf_claim(jwt) do
    with [_header, payload, _signature] <- String.split(jwt, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"csrfToken" => token}} when is_binary(token) <- Jason.decode(json) do
      token
    else
      _ -> nil
    end
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
    Agent.update(jar, fn state -> %{state | cookies: [], csrf_token: nil} end)
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
