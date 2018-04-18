use Mix.Config

config :logger, compile_time_purge_level: :warn

config :logger, :console, level: :warn

config :ecto_poll_queue_example, interval: 0.5
