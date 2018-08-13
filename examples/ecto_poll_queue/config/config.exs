use Mix.Config

config :ecto_poll_queue_example, ecto_repos: [EctoPollQueueExample.Repo]
config :ecto_poll_queue_example, interval: 0.5

config :logger, compile_time_purge_level: :warn
config :logger, :console, level: :warn

import_config "#{Mix.env()}.exs"
