defmodule UnifiClient.Cloud.ClientTest do
  use ExUnit.Case, async: true

  alias UnifiClient.Cloud.Client

  describe "new/1" do
    test "creates client with API key" do
      assert {:ok, client} = Client.new(api_key: "test-api-key")

      assert client.api_key == "test-api-key"
      assert client.base_url == "https://api.ui.com"
      assert client.timeout == 30_000
    end

    test "allows custom base URL" do
      {:ok, client} = Client.new(api_key: "test-key", base_url: "https://custom.api.com")
      assert client.base_url == "https://custom.api.com"
    end

    test "allows custom timeout" do
      {:ok, client} = Client.new(api_key: "test-key", timeout: 60_000)
      assert client.timeout == 60_000
    end

    test "returns error for missing API key" do
      assert {:error, :api_key_required} = Client.new([])
    end

    test "returns error for empty API key" do
      assert {:error, :invalid_api_key} = Client.new(api_key: "")
    end

    test "initializes req client with correct headers" do
      {:ok, client} = Client.new(api_key: "my-api-key")
      assert %Req.Request{} = client.req

      # Check that API key header is set
      headers = client.req.headers
      assert Enum.any?(headers, fn {k, v} -> k == "x-api-key" && v == ["my-api-key"] end)
    end
  end

  describe "new!/1" do
    test "returns client on success" do
      client = Client.new!(api_key: "test-key")
      assert client.api_key == "test-key"
    end

    test "raises on error" do
      assert_raise ArgumentError, fn ->
        Client.new!([])
      end
    end
  end
end
