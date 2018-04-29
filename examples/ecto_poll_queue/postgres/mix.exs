defmodule EctoPollQueueExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :ecto_poll_queue_example,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
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
      extra_applications: [:logger],
      mod: {EctoPollQueueExample.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:honeydew, path: "../../.."},
      {:ecto, "~> 2.0"},
      {:postgrex, "~> 0.13"},
      {:dialyxir, "~> 0.5", only: :test, runtime: false}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "ecto.reset": ["ecto.drop --quiet", "ecto.setup"],
      test: ["ecto.reset", "test"]
    ]
  end
end
