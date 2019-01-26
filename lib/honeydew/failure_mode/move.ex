defmodule Honeydew.FailureMode.Move do
  @moduledoc """
  Instructs Honeydew to move a job to another queue on failure.

  ## Example

  Move this job to the `:failed` queue, on failure.

  ```elixir
  Honeydew.start_queue(:my_queue, failure_mode: {#{inspect __MODULE__},
                                                 queue: :failed})
  ```
  """

  alias Honeydew.Job
  alias Honeydew.Queue

  require Logger

  @behaviour Honeydew.FailureMode

  @impl true
  def validate_args!([queue: {:global, queue}]) when is_atom(queue) or is_binary(queue), do: :ok
  def validate_args!([queue: queue]), do: validate_args!(queue: {:global, queue})
  def validate_args!(args), do: raise ArgumentError, "You provided arguments (#{inspect args}) to the Move failure mode, it's expecting [queue: to_queue]"

  @impl true
  def handle_failure(%Job{queue: queue, from: from} = job, reason, [queue: to_queue]) do
    Logger.info "Job failed because #{inspect reason}, moving to #{inspect to_queue}: #{inspect job}"

    # tell the queue that that job can be removed.
    queue
    |> Honeydew.get_queue
    |> Queue.ack(job)

    {:ok, job} =
      %{job | queue: to_queue}
      |> Honeydew.enqueue

    # send the error to the awaiting process, if necessary
    with {owner, _ref} <- from,
      do: send(owner, %{job | result: {:moved, reason}})
  end
end
