use Mix.Config

config :logger, compile_time_purge_level: :warn

config :logger, :console, level: :warn

config :ecto_poll_queue, interval: 500
