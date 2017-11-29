defmodule Honeydew.FailureMode.Abandon do
  @moduledoc """
  Instructs Honeydew to abandon a job on failure.

  ## Example

      Honeydew.queue_spec(:my_queue, failure_mode: #{inspect __MODULE__})

  """
  require Logger
  alias Honeydew.Job

  @behaviour Honeydew.FailureMode

  @impl true
  def validate_args!([]), do: :ok
  def validate_args!(args), do: raise ArgumentError, "You provided arguments (#{inspect args}) to the Abandon failure mode, it only accepts an empty list"

  @impl true
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
