use Mix.Config

config :logger,
  compile_time_purge_level: :warn

config :logger, :console,
  level: :warn
