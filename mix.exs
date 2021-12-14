defmodule Honeydew.Mixfile do
  use Mix.Project

  @source_url "https://github.com/koudelka/honeydew"
  @version "1.5.0"

  def project do
    [
      app: :honeydew,
      version: @version,
      elixir: "~> 1.12.0",
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      deps: deps(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:mnesia, :ex_unit],
        flags: [
          :unmatched_returns,
          :error_handling,
          :race_conditions,
          :no_opaque
        ]
      ],
      preferred_cli_env: [
        docs: :docs,
        "hex.publish": :docs
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger],
      included_applications: [:mnesia],
      mod: {Honeydew.Application, []}
    ]
  end

  defp deps do
    [
      {:ecto, "~> 3.0", optional: true, only: [:dev, :prod]},
      {:ex_doc, ">= 0.0.0", only: :docs, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
      # {:eflame, git: "git@github.com:slfritchie/eflame", only: :dev},
    ]
  end

  defp package do
    [
      description: "Pluggable local/clusterable job queue focused on safety.",
      maintainers: ["Michael Shapiro"],
      licenses: ["MIT"],
      links: %{
        Changelog: "https://hexdocs.pm/honeydew/changelog.html",
        GitHub: @source_url
      }
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"],
        "guides/api.md": [],
        "guides/caveats.md": [],
        "guides/dispatchers.md": [],
        "guides/job_lifecycle.md": [],
        "guides/queues.md": [],
        "guides/success_and_failure_modes.md": [],
        "guides/workers.md": []
      ],
      main: "readme",
      assets: "assets",
      source_url: @source_url,
      source_ref: @version,
      formatters: ["html"]
    ]
  end
end
