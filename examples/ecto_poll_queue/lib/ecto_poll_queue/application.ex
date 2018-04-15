defmodule EctoPollQueue.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Honeydew.PollQueue
  alias Honeydew.EctoSource
  alias Honeydew.FailureMode.Retry
  alias EctoPollQueue.Repo
  alias EctoPollQueue.Photo
  alias EctoPollQueue.User
  alias EctoPollQueue.ClassifyPhoto
  alias EctoPollQueue.Notify
  import EctoPollQueue.User, only: [notify_queue: 0]
  import EctoPollQueue.Photo, only: [classify_queue: 0]

  def start(_type, _args) do
    interval = Application.get_env(:ecto_poll_queue, :interval, 1_000)

    children = [
      Repo,
      Honeydew.queue_spec(
        notify_queue(),
        queue: {PollQueue, [EctoSource, [schema: User, repo: Repo, interval: interval]]}
      ),
      Honeydew.worker_spec(notify_queue(), Notify),

      Honeydew.queue_spec(
        classify_queue(),
        queue: {PollQueue, [EctoSource, [schema: Photo, repo: Repo, interval: interval]]},
        failure_mode: {Retry, [times: 1]}
      ),
      Honeydew.worker_spec(classify_queue(), ClassifyPhoto, num: 20)
    ]

    opts = [strategy: :one_for_one, name: EctoPollQueue.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
