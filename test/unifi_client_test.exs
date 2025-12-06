defmodule UnifiClientTest do
  use ExUnit.Case

  test "version/0 returns version string" do
    assert UnifiClient.version() == "0.1.0"
  end
end
