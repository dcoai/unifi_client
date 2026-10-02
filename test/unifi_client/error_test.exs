defmodule UnifiClient.ErrorTest do
  use ExUnit.Case, async: true

  alias UnifiClient.{Auth, Client, Error, Response}

  @stub __MODULE__.Stub

  # Every body shape a console has been seen to put an error message in, or
  # that must fall back to the default. `nil` means "no message here".
  @bodies [
    {%{"error" => "Invalid credentials"}, "Invalid credentials"},
    {%{"error" => %{"code" => 401, "message" => "Unauthorized"}}, "Unauthorized"},
    {%{"message" => "Session expired"}, "Session expired"},
    {%{"message" => %{"detail" => "x"}}, nil},
    {%{"meta" => %{"rc" => "error", "msg" => "api.err.LoginRequired"}}, "api.err.LoginRequired"},
    {%{"meta" => %{"rc" => "error", "msg" => %{"x" => 1}}}, nil},
    {%{"errors" => ["bad password"]}, "bad password"},
    {%{"errors" => [%{"message" => "bad password"}]}, "bad password"},
    {%{"errors" => []}, nil},
    {%{"code" => 401}, nil},
    {%{"error" => 0}, nil},
    {"<html>Unauthorized</html>", nil},
    {[1, 2], nil},
    {nil, nil}
  ]

  describe "message_from_body/1" do
    test "finds the message in every known shape and nil otherwise" do
      for {body, expected} <- @bodies do
        assert Error.message_from_body(body) == expected, "body: #{inspect(body)}"
      end
    end
  end

  describe "Response.parse/1 on a 401" do
    test "the message is the console's, or the default, and the body is kept" do
      for {body, expected} <- @bodies do
        assert {:error, %Error{code: :authentication_failed} = e} =
                 Response.parse(%Req.Response{status: 401, body: body})

        assert e.message == (expected || "Authentication failed"), "body: #{inspect(body)}"
        assert e.reason == %{status: 401, body: body}
      end
    end

    test "the nested Protect export body yields its inner message" do
      body = %{"error" => %{"code" => 401, "message" => "Unauthorized"}}

      assert {:error, %Error{message: "Unauthorized", reason: %{body: ^body}}} =
               Response.parse(%Req.Response{status: 401, body: body})
    end
  end

  describe "Auth.login/2 on a refused login" do
    setup do
      {:ok, client} =
        Client.new(
          host: "udm.local",
          username: "svc",
          password: "pw",
          req_options: [plug: {Req.Test, @stub}]
        )

      %{client: client}
    end

    test "401 and 403 carry the console's message or the default", %{client: client} do
      for status <- [401, 403], {body, expected} <- @bodies do
        Req.Test.stub(@stub, fn conn ->
          conn = Plug.Conn.put_status(conn, status)

          case body do
            binary when is_binary(binary) -> Plug.Conn.send_resp(conn, status, binary)
            nil -> Plug.Conn.send_resp(conn, status, "")
            json -> Req.Test.json(conn, json)
          end
        end)

        default = if status == 401, do: "Invalid username or password", else: "Access denied"

        assert {:error, %Error{code: :authentication_failed} = e} = Auth.login(client)
        assert e.message == (expected || default), "#{status} body: #{inspect(body)}"
        assert %{status: ^status} = e.reason
      end
    end
  end

  describe "the message invariant" do
    # Every constructor, and every Response.parse/1 branch, over every body
    # shape above. Adding a path that can yield a non-binary message must
    # fail here.
    defp constructed do
      bodies = Enum.map(@bodies, &elem(&1, 0))

      [
        Error.new("m"),
        Error.new("m", :x, :reason),
        Error.authentication_error(),
        Error.authentication_error("m"),
        Error.authentication_error("m", %{status: 401}),
        Error.not_found(),
        Error.not_found("Device"),
        Error.connection_error(%Req.TransportError{reason: :timeout}),
        Error.connection_error(%Req.TransportError{reason: :econnrefused}),
        Error.app_unavailable(:protect),
        Error.api_error(%{"error" => "m", "name" => "NotFound", "statusCode" => 404}),
        Error.api_error(%{"meta" => %{"rc" => "error"}}),
        Error.http_error(500),
        Error.http_error(418, %{"error" => %{"nested" => true}})
      ] ++
        Enum.map(bodies, &Error.rate_limited/1) ++
        Enum.flat_map(bodies, &api_errors/1)
    end

    defp api_errors(%{} = body), do: [Error.api_error(body)]
    defp api_errors(_), do: []

    defp parsed do
      statuses = [200, 400, 401, 403, 404, 429, 500]

      bodies =
        Enum.map(@bodies, &elem(&1, 0)) ++
          [
            %{"error" => "m", "name" => "Unauthorized", "statusCode" => 401},
            %{"code" => "AUTHENTICATION_FAILED_LIMIT_REACHED"},
            %{"meta" => %{"rc" => "ok"}, "data" => []}
          ]

      for status <- statuses,
          body <- bodies,
          {:error, error} <- [Response.parse(%Req.Response{status: status, body: body})],
          do: error
    end

    test "every error's message is a binary, and so is Exception.message/1" do
      errors = constructed() ++ parsed()
      assert length(errors) > 100

      for error <- errors do
        assert is_binary(error.message), "non-binary message: #{inspect(error)}"
        assert is_binary(Exception.message(error))
      end
    end

    test "new/3 refuses a non-binary message" do
      for bad <- [nil, %{"code" => 401}, :atom, ["list"]] do
        assert_raise FunctionClauseError, fn -> Error.new(bad, :x) end
      end
    end

    test "api_error/1 with a non-binary meta.msg falls back to the rc" do
      assert %Error{message: "API error: error", code: :error} =
               Error.api_error(%{"meta" => %{"rc" => "error", "msg" => %{"x" => 1}}})
    end
  end
end
