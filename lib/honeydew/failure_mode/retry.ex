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
  # if everything looks right, validate the 'finally' mode args, too
  def validate_args!([times: times, finally: {module, args}]) when is_integer(times)
                                                               and times > 0
                                                               and is_atom(module)
                                                               and is_list(args) do
    module.validate_args!(args)
  end

  def validate_args!([times: times]) when is_integer(times) and times > 0, do: :ok
  def validate_args!(args), do: raise ArgumentError, "You provided arguments (#{inspect args}) to the Retry failure mode, it's expecting either [times: times] or [times: times, finally: {module, args}]"

  @impl true
  def handle_failure(job, reason, [times: times]), do:
    handle_failure(job, reason, [times: times, finally: {Abandon, []}])

  def handle_failure(%Job{failure_private: nil} = job, reason, [times: times, finally: finally]), do:
    handle_failure(%{job | failure_private: times}, reason, finally)

  def handle_failure(%Job{failure_private: 0} = job, reason, [times: _times, finally: {final_mode, final_args}]), do:
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
