use Mix.Config

config :ecto_poll_queue, ecto_repos: [EctoPollQueue.Repo]

config :ecto_poll_queue, EctoPollQueue.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "honeydew_#{Mix.env()}",
  username: "root",
  password: "",
  hostname: "localhost",
  port: 26257

import_config "#{Mix.env()}.exs"
