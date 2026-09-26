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

  # The Elixir a caller is promised and the Elixir this project runs are the
  # same two-places problem: `mix.exs` declares a floor, CI pins an image,
  # and nothing connects them. `~> 1.15` stood for five minor versions the
  # suite had never once run.
  #
  # So the floor must name the version CI tests. When the image moves this
  # fails, and the answer is a decision rather than a silent widening of
  # the promise: raise the floor with it, or add the old floor to CI as a
  # second job and go on supporting it.
  test "the declared Elixir floor is the version CI actually runs" do
    requirement = Mix.Project.config()[:elixir]

    [_, ci_version] =
      Regex.run(~r{ELIXIR_IMAGE:\s*hexpm/elixir:(\d+\.\d+\.\d+)}, File.read!(".gitlab-ci.yml"))

    assert Version.match?(ci_version, requirement),
           "CI runs Elixir #{ci_version}, which does not satisfy mix.exs's #{requirement}"

    [_, floor] = Regex.run(~r/^~> (\d+\.\d+)/, requirement)
    {:ok, ci} = Version.parse(ci_version)

    assert floor == "#{ci.major}.#{ci.minor}",
           "mix.exs claims Elixir #{requirement} but CI runs #{ci_version}: " <>
             "either raise the floor, or test the floor you claim"
  end
end
