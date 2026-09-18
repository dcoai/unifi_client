defmodule UnifiClient.ProtectTest do
  use ExUnit.Case, async: true

  alias UnifiClient.{Client, Error, Protect}
  alias UnifiClient.Protect.{API, Time}

  @stub __MODULE__.Stub

  setup do
    {:ok, udm} = Client.new(host: "unvr.local")
    {:ok, controller} = Client.new(host: "ctl.local", type: :controller)
    %{udm: udm, controller: controller, plug: [plug: {Req.Test, @stub}]}
  end

  describe "bootstrap/1 and nvr/1" do
    test "hit the Protect application", %{udm: udm, plug: plug} do
      Req.Test.stub(@stub, fn conn ->
        case conn.request_path do
          "/proxy/protect/api/bootstrap" ->
            Req.Test.json(conn, %{"lastUpdateId" => "u1", "cameras" => [], "nvr" => %{}})

          "/proxy/protect/api/nvr" ->
            Req.Test.json(conn, %{"name" => "UNVR", "version" => "5.0.0"})
        end
      end)

      assert {:ok, %{"lastUpdateId" => "u1"}} = Protect.bootstrap(udm, plug)
      assert {:ok, %{"name" => "UNVR"}} = Protect.nvr(udm, plug)
    end

    test "are unavailable on a :controller", %{controller: controller} do
      assert {:error, %Error{code: :app_unavailable}} = Protect.bootstrap(controller)
      assert {:error, %Error{code: :app_unavailable}} = Protect.nvr(controller)
    end
  end

  describe "Protect.API.with_query/2" do
    test "drops nil values and omits the ? when nothing remains" do
      assert API.with_query("/api/x", a: nil, b: nil) == "/api/x"
      assert API.with_query("/api/x", []) == "/api/x"
      assert API.with_query("/api/x", a: 1, b: nil, c: "two") == "/api/x?a=1&c=two"
    end
  end

  describe "Protect.Time" do
    test "to_ms/1 converts DateTime and passes integers" do
      assert Time.to_ms(~U[2026-09-17 12:00:00Z]) == 1_789_646_400_000
      assert Time.to_ms(1_789_646_400_000) == 1_789_646_400_000
      assert Time.to_ms(~U[1970-01-01 00:00:00.500Z]) == 500
    end

    test "to_ms_or_nil/1 passes nil" do
      assert Time.to_ms_or_nil(nil) == nil
      assert Time.to_ms_or_nil(~U[1970-01-01 00:00:01Z]) == 1000
    end

    test "to_ms/1 rejects negative integers" do
      assert_raise FunctionClauseError, fn -> Time.to_ms(-1) end
    end
  end
end
