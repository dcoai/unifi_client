defmodule UnifiClient.VersionTest do
  use ExUnit.Case, async: true

  @moduledoc """
  The version is written in two places a reader trusts — `mix.exs` and the
  changelog's newest heading — and they must agree. A release whose
  changelog describes a different version than the one it ships is worse
  than no changelog.
  """

  test "the changelog's newest release is the version being shipped" do
    version = Mix.Project.config()[:version]

    [newest] =
      "CHANGELOG.md"
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "## ["))
      |> Enum.take(1)

    assert newest =~ "[#{version}]", "CHANGELOG.md starts with #{newest}, mix.exs says #{version}"
  end

  test "the docs point at a tag named after the version" do
    assert Mix.Project.config()[:docs][:source_ref] == "v#{Mix.Project.config()[:version]}"
  end
end
