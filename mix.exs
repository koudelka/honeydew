defmodule Honeydew.Mixfile do
  use Mix.Project

  @version "0.0.5"

  def project do
    [app: :honeydew,
     version: @version,
     elixir: "~> 1.0",
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
    [contributors: ["Michael Shapiro"],
     licenses: ["MIT"],
     links: %{"GitHub": "https://github.com/koudelka/elixir-honeydew"}]
  end
end
