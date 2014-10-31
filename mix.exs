defmodule Honeydew.Mixfile do
  use Mix.Project

  def project do
    [app: :honeydew,
     version: "0.0.1",
     elixir: "~> 1.0",
     deps: deps,
     package: [
       contributors: ["Michael Shapiro"],
       licenses: ["MIT"],
       links: %{github: "https://github.com/koudelka/elixir-honeydew"}
     ],
     description: """
     Elixir worker pool with a centralized job queue and permanent workers.
     """]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [
      mod: {Honeydew, []},
      applications: [:logger]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type `mix help deps` for more examples and options
  defp deps do
    []
  end
end
