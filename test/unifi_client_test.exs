defmodule UnifiClientTest do
  use ExUnit.Case

  doctest UnifiClient

  test "version/0 returns version string" do
    assert UnifiClient.version() == Mix.Project.config()[:version]
  end
end
