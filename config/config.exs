use Mix.Config

config :sasl,
  errlog_type: :error

import_config "#{Mix.env}.exs"
