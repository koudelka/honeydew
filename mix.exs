defmodule Honeydew.Mixfile do
  use Mix.Project

  @version "0.0.10"

  def project do
    [app: :honeydew,
     version: @version,
     elixir: "~> 1.2.3",
     deps: deps,
     package: package,
     description: "Job queue + worker pool with permanent workers."]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      # mod: {Honeydew, []},
      applications: [:logger]
    ]
  end

  defp deps do
    []
  end

  defp package do
    [maintainers: ["Michael Shapiro"],
     licenses: ["MIT"],
     links: %{"GitHub": "https://github.com/koudelka/elixir-honeydew"}]
  end
end
