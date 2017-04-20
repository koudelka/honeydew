defmodule Honeydew.FailureMode.Abandon do
  require Logger
  alias Honeydew.Job

  # @behaviour Honeydew.FailureMode

  def handle_failure(%Job{queue: queue, from: from} = job, reason, []) do
    Logger.warn "Job failed because #{inspect reason}, abandoning: #{inspect job}"

    # tell the queue that that job can be removed.
    queue
    |> Honeydew.get_queue
    |> GenServer.cast({:ack, job})

    # send the error to the awaiting process, if necessary
    with {owner, _ref} <- from,
      do: send(owner, %{job | result: {:error, reason}})
  end
end
