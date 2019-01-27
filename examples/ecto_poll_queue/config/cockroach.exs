use Mix.Config

config :ecto_poll_queue_example, EctoPollQueueExample.Repo,
  adapter: Ecto.Adapters.Postgres,
  database: "honeydew_test",
  username: "root",
  password: "",
  hostname: "localhost",
  port: 26257,
  # removes lock on migration table for cockroach compat
  # https://github.com/cockroachdb/cockroach/issues/6583
  migration_lock: nil
