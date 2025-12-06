defmodule UnifiClient.ResponseTest do
  use ExUnit.Case, async: true

  alias UnifiClient.Response

  describe "parse/1" do
    test "parses successful response with data array" do
      response = %Req.Response{
        status: 200,
        body: %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"id" => "1"}, %{"id" => "2"}]
        }
      }

      assert {:ok, [%{"id" => "1"}, %{"id" => "2"}]} = Response.parse(response)
    end

    test "parses successful response without meta wrapper" do
      response = %Req.Response{
        status: 200,
        body: [%{"id" => "1"}]
      }

      assert {:ok, [%{"id" => "1"}]} = Response.parse(response)
    end

    test "returns error for API error response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "meta" => %{"rc" => "error", "msg" => "Invalid request"}
        }
      }

      assert {:error, error} = Response.parse(response)
      assert error.message == "Invalid request"
    end

    test "returns authentication error for 401" do
      response = %Req.Response{
        status: 401,
        body: %{"error" => "Invalid credentials"}
      }

      assert {:error, error} = Response.parse(response)
      assert error.code == :authentication_failed
    end

    test "returns not found error for 404" do
      response = %Req.Response{status: 404, body: nil}

      assert {:error, error} = Response.parse(response)
      assert error.code == :not_found
    end

    test "returns HTTP error for other status codes" do
      response = %Req.Response{status: 500, body: %{"error" => "Internal error"}}

      assert {:error, error} = Response.parse(response)
      assert error.code == :http_error
    end
  end

  describe "parse_one/1" do
    test "returns single item from array" do
      response = %Req.Response{
        status: 200,
        body: %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"id" => "1"}]
        }
      }

      assert {:ok, %{"id" => "1"}} = Response.parse_one(response)
    end

    test "returns first item from multiple items" do
      response = %Req.Response{
        status: 200,
        body: %{
          "meta" => %{"rc" => "ok"},
          "data" => [%{"id" => "1"}, %{"id" => "2"}]
        }
      }

      assert {:ok, %{"id" => "1"}} = Response.parse_one(response)
    end

    test "returns not found for empty array" do
      response = %Req.Response{
        status: 200,
        body: %{
          "meta" => %{"rc" => "ok"},
          "data" => []
        }
      }

      assert {:error, error} = Response.parse_one(response)
      assert error.code == :not_found
    end
  end

  describe "parse_empty/1" do
    test "returns :ok for successful response" do
      response = %Req.Response{
        status: 200,
        body: %{
          "meta" => %{"rc" => "ok"},
          "data" => []
        }
      }

      assert :ok = Response.parse_empty(response)
    end

    test "returns error for failed response" do
      response = %Req.Response{status: 401, body: nil}

      assert {:error, _} = Response.parse_empty(response)
    end
  end
end
