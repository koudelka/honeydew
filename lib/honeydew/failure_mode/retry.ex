defmodule Honeydew.FailureMode.Retry do
  require Logger
  alias Honeydew.Job
  alias Honeydew.FailureMode.Abandon

  @behaviour Honeydew.FailureMode

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
