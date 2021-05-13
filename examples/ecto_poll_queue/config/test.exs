use Mix.Config

config :logger,
  compile_time_purge_matching: [
    [level_lower_than: :warn]
  ],
  console: [level: : warn]

config :ecto_poll_queue_example, interval: 0.5
