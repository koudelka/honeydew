use Mix.Config

config :ecto_poll_queue_example, ecto_repos: [EctoPollQueueExample.Repo]

config :ecto_poll_queue_example, EctoPollQueueExample.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "honeydew_#{Mix.env()}",
  username: "root",
  password: "",
  hostname: "localhost",
  port: 26257

import_config "#{Mix.env()}.exs"
