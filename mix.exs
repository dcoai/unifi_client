defmodule UnifiClient.MixProject do
  use Mix.Project

  @version "0.2.1"
  @source_url "https://github.com/dcoai/unifi_client"

  def project do
    [
      app: :unifi_client,
      version: @version,
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "UnifiClient",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :ssl]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:websockex, "~> 0.4"},

      # Dev/Test
      {:mox, "~> 1.0", only: :test},
      {:plug, "~> 1.0", only: :test},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    An Elixir client for UniFi Network and UniFi Protect.
    Supports UDM Pro, UniFi OS consoles, and UniFi Cloud.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url, "Changelog" => @source_url <> "/blob/main/CHANGELOG.md"},
      # The defaults plus the specification and the examples: a tarball that
      # can rebuild its own documentation, and that carries the twelve
      # scripts the README sends a reader to.
      files: ~w(lib examples .formatter.exs mix.exs README.md LICENSE CHANGELOG.md spec.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "spec.md",
        # Titled, because two files called README.md would otherwise fight
        # over the same page.
        "examples/README.md": [filename: "examples", title: "Examples"]
      ],
      source_ref: "v#{@version}"
    ]
  end
end
