defmodule UnifiClient.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourusername/unifi_client"

  def project do
    [
      app: :unifi_client,
      version: @version,
      elixir: "~> 1.15",
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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    An Elixir client for the UniFi Network Controller API.
    Supports UDM Pro, UniFi OS consoles, and UniFi Cloud.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
