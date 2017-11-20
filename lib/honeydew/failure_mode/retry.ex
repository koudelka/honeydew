defmodule Honeydew.FailureMode.Retry do
  alias Honeydew.FailureMode.Move
  @moduledoc """
  Instructs Honeydew to retry a job `x` times on failure.

  ## Examples

  Retry jobs in this queue 3 times:

      Honeydew.queue_spec(:my_queue, failure_mode: {#{inspect __MODULE__}, [times: 3]})

  Retry jobs in this queue 3 times and then move to another queue:

      Honeydew.queue_spec(:my_queue,
        failure_mode: {
          #{inspect __MODULE__},
          [times: 3, finally: {#{inspect Move}, [queue: :another_queue]}]
        }
      )
  """
  alias Honeydew.FailureMode.Abandon
  alias Honeydew.Job

  require Logger

  @behaviour Honeydew.FailureMode

  @impl true
  def handle_failure(job, reason, [times: times]), do:
    handle_failure(job, reason, [times: times, finally: {Abandon, []}])

  def handle_failure(%Job{failure_private: nil} = job, reason, [times: times, finally: finally]), do:
    handle_failure(%{job | failure_private: times}, reason, finally)

  def handle_failure(%Job{failure_private: 1} = job, reason, [times: _times, finally: {final_mode, final_args}]), do:
    final_mode.handle_failure(%{job | failure_private: nil}, reason, final_args)

  def handle_failure(%Job{queue: queue, from: from, failure_private: tries_left} = job, reason, _args) do
    tries_left = tries_left - 1
    job = %{job | failure_private: tries_left}

    Logger.info "Job failed because #{inspect reason}, retrying #{tries_left} more times, job: #{inspect job}"

    queue
    |> Honeydew.get_queue
    |> GenServer.cast({:nack, job})

    # send the error to the awaiting process, if necessary
    with {owner, _ref} <- from,
      do: send(owner, %{job | result: {:retrying, reason}})
  end
end
