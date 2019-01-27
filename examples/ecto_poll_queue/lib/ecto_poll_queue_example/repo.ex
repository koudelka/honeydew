defmodule EctoPollQueueExample.Repo do
  use Ecto.Repo,
    otp_app: :ecto_poll_queue_example,
    adapter: Ecto.Adapters.Postgres
end
