defmodule Honeydew.Mixfile do
  use Mix.Project

  def project do
    [app: :honeydew,
     version: "1.0.0-rc2",
     elixir: "~> 1.4.0",
     deps: deps(),
     package: package(),
     description: "Pluggable local/remote job queue + worker pool with permanent workers."]
  end

  # Configuration for the OTP application
  #
  # Type `mix help compile.app` for more information
  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:riakc, ">= 2.4.1", only: :dev},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp package do
    [maintainers: ["Michael Shapiro"],
     licenses: ["MIT"],
     links: %{"GitHub": "https://github.com/koudelka/elixir-honeydew"}]
  end
end
