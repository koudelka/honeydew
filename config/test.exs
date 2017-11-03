use Mix.Config

config :honeydew,
  disorder: Honeydew.DisorderSandbox

config :logger,
  compile_time_purge_level: :warn

config :logger, :console,
  level: :warn
