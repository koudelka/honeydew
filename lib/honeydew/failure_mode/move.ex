defmodule Honeydew.FailureMode.Move do
  require Logger
  alias Honeydew.Job

  @behaviour Honeydew.FailureMode

  def handle_failure(%Job{queue: queue, from: from} = job, reason, [queue: to_queue]) do
    Logger.info "Job failed because #{inspect reason}, moving to #{inspect to_queue}: #{inspect job}"

    # tell the queue that that job can be removed.
    queue
    |> Honeydew.get_queue
    |> GenServer.cast({:ack, job})

    {:ok, job} =
      %{job | queue: to_queue}
      |> Honeydew.enqueue

    # send the error to the awaiting process, if necessary
    with {owner, _ref} <- from,
      do: send(owner, %{job | result: {:moved, reason}})
  end
end
