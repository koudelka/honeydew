defmodule EctoPollQueueExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_poll_queue_example,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(Mix.env),
      dialyzer: [
        flags: [
          :unmatched_returns,
          :error_handling,
          :race_conditions,
          :no_opaque
        ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :mix],
      mod: {EctoPollQueueExample.Application, []}
    ]
  end

  defp deps do
    [
      {:honeydew, path: "../.."},
      {:dialyxir, "~> 0.5", only: [:cockroach, :postgres], runtime: false}
    ]
  end

  defp deps(:cockroach) do
    [
     {:ecto, "~> 3.0"},
     {:postgrex, github: "activeprospect/postgrex", branch: "v0.14.1-cdb", override: true},
     {:ecto_sql, github: "activeprospect/ecto_sql", branch: "v3.0.5-cdb", override: true},
     {:jason, "~> 1.0"},
     ] ++ deps()
  end

  defp deps(:postgres) do
    [{:ecto_sql, "~> 3.0"},
     {:postgrex, "~> 0.13"}] ++ deps()
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"],
      test: ["ecto.reset", "test"]
    ]
  end
end
