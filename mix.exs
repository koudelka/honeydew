defmodule Honeydew.Mixfile do
  use Mix.Project

  @version "1.0.4"

  def project do
    [app: :honeydew,
     version: @version,
     elixir: "~> 1.4",
     docs: docs(),
     deps: deps(),
     package: package(),
     description: "Pluggable local/remote job queue + worker pool with permanent workers.",
     dialyzer: [plt_add_apps: [:mnesia]]]
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
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:dialyxir, "~> 0.5", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [maintainers: ["Michael Shapiro"],
     licenses: ["MIT"],
     links: %{"GitHub": "https://github.com/koudelka/elixir-honeydew"}]
  end

  defp docs do
    [extras: ["README.md"],
     source_url: "https://github.com/koudelka/honeydew",
     source_ref: @version,
     assets: "assets",
     main: "readme"]
  end
end
