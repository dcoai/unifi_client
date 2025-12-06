defmodule UnifiClient.ClientTest do
  use ExUnit.Case, async: true

  alias UnifiClient.Client

  describe "new/1" do
    test "creates client with required options" do
      assert {:ok, client} =
               Client.new(
                 host: "192.168.1.1",
                 username: "admin",
                 password: "secret"
               )

      assert client.host == "192.168.1.1"
      assert client.username == "admin"
      assert client.password == "secret"
      assert client.type == :udm_pro
      assert client.port == 443
      assert client.verify_ssl == false
    end

    test "defaults to UDM Pro with port 443" do
      {:ok, client} = Client.new(host: "192.168.1.1")
      assert client.type == :udm_pro
      assert client.port == 443
    end

    test "uses port 8443 for standard controller" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :controller)
      assert client.type == :controller
      assert client.port == 8443
    end

    test "allows custom port" do
      {:ok, client} = Client.new(host: "192.168.1.1", port: 9443)
      assert client.port == 9443
    end

    test "returns error for missing host" do
      assert {:error, :host_required} = Client.new([])
      assert {:error, :host_required} = Client.new(host: nil)
      assert {:error, :host_required} = Client.new(host: "")
    end

    test "returns error for invalid type" do
      assert {:error, :invalid_type} = Client.new(host: "192.168.1.1", type: :invalid)
    end

    test "initializes cookie jar" do
      {:ok, client} = Client.new(host: "192.168.1.1")
      assert is_pid(client.cookie_jar)
    end

    test "initializes req client" do
      {:ok, client} = Client.new(host: "192.168.1.1")
      assert %Req.Request{} = client.req
    end
  end

  describe "new!/1" do
    test "returns client on success" do
      client = Client.new!(host: "192.168.1.1")
      assert client.host == "192.168.1.1"
    end

    test "raises on error" do
      assert_raise ArgumentError, fn ->
        Client.new!([])
      end
    end
  end

  describe "base_url/1" do
    test "returns correct URL for UDM Pro" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :udm_pro)
      assert Client.base_url(client) == "https://192.168.1.1:443"
    end

    test "returns correct URL for standard controller" do
      {:ok, client} = Client.new(host: "192.168.1.100", type: :controller)
      assert Client.base_url(client) == "https://192.168.1.100:8443"
    end
  end

  describe "api_prefix/1" do
    test "returns /proxy/network for UDM Pro" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :udm_pro)
      assert Client.api_prefix(client) == "/proxy/network"
    end

    test "returns empty string for standard controller" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :controller)
      assert Client.api_prefix(client) == ""
    end
  end

  describe "login_endpoint/1" do
    test "returns /api/auth/login for UDM Pro" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :udm_pro)
      assert Client.login_endpoint(client) == "/api/auth/login"
    end

    test "returns /api/login for standard controller" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :controller)
      assert Client.login_endpoint(client) == "/api/login"
    end
  end

  describe "api_url/2" do
    test "adds prefix for UDM Pro" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :udm_pro)
      assert Client.api_url(client, "/api/s/default/stat/device") ==
               "/proxy/network/api/s/default/stat/device"
    end

    test "no prefix for standard controller" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :controller)
      assert Client.api_url(client, "/api/s/default/stat/device") ==
               "/api/s/default/stat/device"
    end
  end

  describe "site_url/3" do
    test "builds correct site URL for UDM Pro" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :udm_pro)
      assert Client.site_url(client, "default", "/stat/device") ==
               "/proxy/network/api/s/default/stat/device"
    end

    test "builds correct site URL for standard controller" do
      {:ok, client} = Client.new(host: "192.168.1.1", type: :controller)
      assert Client.site_url(client, "mysite", "/stat/device") ==
               "/api/s/mysite/stat/device"
    end
  end

  describe "state management" do
    test "put_csrf_token/2 updates token" do
      {:ok, client} = Client.new(host: "192.168.1.1")
      assert client.csrf_token == nil

      client = Client.put_csrf_token(client, "test-token")
      assert client.csrf_token == "test-token"
    end

    test "mark_logged_in/1 sets logged_in flag" do
      {:ok, client} = Client.new(host: "192.168.1.1")
      assert client.logged_in == false

      client = Client.mark_logged_in(client)
      assert client.logged_in == true
    end

    test "mark_logged_out/1 clears state" do
      {:ok, client} = Client.new(host: "192.168.1.1")
      client = Client.put_csrf_token(client, "token")
      client = Client.mark_logged_in(client)

      client = Client.mark_logged_out(client)
      assert client.logged_in == false
      assert client.csrf_token == nil
    end
  end
end
