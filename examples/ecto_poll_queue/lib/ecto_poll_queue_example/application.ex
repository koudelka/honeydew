defmodule EctoPollQueueExample.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Honeydew.EctoPollQueue
  alias Honeydew.FailureMode.Retry
  alias Honeydew.FailureMode.ExponentialRetry
  alias EctoPollQueueExample.Repo
  alias EctoPollQueueExample.Photo
  alias EctoPollQueueExample.User
  alias EctoPollQueueExample.ClassifyPhoto
  alias EctoPollQueueExample.Notify

  import EctoPollQueueExample.User, only: [notify_queue: 0]
  import EctoPollQueueExample.Photo, only: [classify_queue: 0]

  def start(_type, _args) do
    children = [Repo]
    opts = [strategy: :one_for_one, name: EctoPollQueueExample.Supervisor]
    {:ok, supervisor} = Supervisor.start_link(children, opts)

    notify_queue_args = queue_args(User) ++ [run_if: ~s{NAME IS NULL OR NAME != 'dont run'}]
    :ok = Honeydew.start_queue(notify_queue(), queue: {EctoPollQueue, notify_queue_args}, failure_mode: {ExponentialRetry, base: 3, times: 3})
    :ok = Honeydew.start_workers(notify_queue(), Notify)

    :ok = Honeydew.start_queue(classify_queue(), queue: {EctoPollQueue, queue_args(Photo)}, failure_mode: {Retry, [times: 1]})
    :ok = Honeydew.start_workers(classify_queue(), ClassifyPhoto, num: 20)

    {:ok, supervisor}
  end

  defp queue_args(schema) do
    poll_interval = Application.get_env(:ecto_poll_queue, :interval, 1)

    queue_args = [schema: schema, repo: Repo, poll_interval: poll_interval]

    if Mix.env == :cockroach do
      Keyword.put(queue_args, :database, :cockroachdb)
    else
      queue_args
    end
  end
end
