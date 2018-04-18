defmodule EctoPollQueueExample.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Honeydew.EctoPollQueue
  alias Honeydew.Workers
  alias Honeydew.FailureMode.Retry
  alias EctoPollQueueExample.Repo
  alias EctoPollQueueExample.Photo
  alias EctoPollQueueExample.User
  alias EctoPollQueueExample.ClassifyPhoto
  alias EctoPollQueueExample.Notify

  import EctoPollQueueExample.User, only: [notify_queue: 0]
  import EctoPollQueueExample.Photo, only: [classify_queue: 0]

  def start(_type, _args) do
    poll_interval = Application.get_env(:ecto_poll_queue, :interval, 1)

    children = [
      Repo,

      {EctoPollQueue, [notify_queue(), schema: User, repo: Repo, poll_interval: poll_interval]},
      {Workers, [notify_queue(), Notify]},

      {EctoPollQueue, [classify_queue(), schema: Photo, repo: Repo, poll_interval: poll_interval, failure_mode: {Retry, [times: 1]}]},
      {Workers, [classify_queue(), ClassifyPhoto, num: 20]},
    ]

    opts = [strategy: :one_for_one, name: EctoPollQueueExample.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
