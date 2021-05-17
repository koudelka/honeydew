defmodule Honeydew.FailureMode.Retry do
  alias Honeydew.Job
  alias Honeydew.Queue
  alias Honeydew.Processes
  alias Honeydew.FailureMode.Abandon
  alias Honeydew.FailureMode.Move

  @moduledoc """
  Instructs Honeydew to retry a job a number of times on failure.

  ## Examples

  Retry jobs in this queue 3 times:

  ```elixir
  Honeydew.start_queue(:my_queue, failure_mode: {#{inspect __MODULE__},
                                                 times: 3})
  ```

  Retry jobs in this queue 3 times and then move to another queue:

  ```elixir
  Honeydew.start_queue(:my_queue,
                       failure_mode: {#{inspect __MODULE__},
                                      times: 3,
                                      finally: {#{inspect Move},
                                                queue: :dead_letters}})
  ```
  """
  require Logger

  @behaviour Honeydew.FailureMode

  @impl true
  def validate_args!(args) when is_list(args) do
    args
    |> Enum.into(%{})
    |> validate_args!(__MODULE__)
  end

  def validate_args!(args, module \\ __MODULE__)

  def validate_args!(%{fun: fun}, _module) when is_function(fun, 3), do: :ok
  def validate_args!(%{fun: bad}, module) do
    raise ArgumentError, "You provided a bad `:fun` argument (#{inspect bad}) to the #{module} failure mode, it's expecting a function or function capture of arity three (job, failure_reason, args), for example: `&#{inspect __MODULE__}.immediate/3`"
  end

  def validate_args!(%{times: times}, module) when not is_integer(times) or times <= 0 do
    raise ArgumentError, "You provided a bad `:times` argument (#{inspect times}) to the #{module} failure mode, it's expecting a positive integer."
  end

  def validate_args!(%{finally: {module, args} = bad}, module) when not is_atom(module) or not is_list(args) do
    raise ArgumentError, "You provided a bad `:finally` argument (#{inspect bad}) to the #{module} failure mode, it's expecting `finally: {module, args}`"
  end

  def validate_args!(%{times: _times, finally: {m, a}}, _module) do
    m.validate_args!(a)
  end

  def validate_args!(%{times: _times}, _module), do: :ok

  def validate_args!(bad, module) do
    raise ArgumentError, "You provided bad arguments (#{inspect bad}) to the #{module} failure mode, at a minimum, it must be a list with a maximum number of retries specified, for example: `[times: 5]`"
  end


  @impl true
  def handle_failure(%Job{queue: queue, from: from} = job, reason, args) when is_list(args) do
    args = Enum.into(args, %{})
    args = Map.merge(%{finally: {Abandon, []},
                       fun: &immediate/3}, args)

    %{fun: fun, finally: {finally_module, finally_args}} = args

    case fun.(job, reason, args) do
      {:cont, private, delay_secs} ->
        job = %Job{job | failure_private: private, delay_secs: delay_secs, result: {:retrying, reason}}

        queue
        |> Processes.get_queue()
        |> Queue.nack(job)

        # send the error to the awaiting process, if necessary
        with {owner, _ref} <- from,
          do: send(owner, %{job | result: {:retrying, reason}})

      :halt ->
        finally_module.handle_failure(%{job | failure_private: nil, delay_secs: 0}, reason, finally_args)
    end
  end

  def immediate(%Job{failure_private: nil} = job, reason, args) do
    immediate(%Job{job | failure_private: 0}, reason, args)
  end

  def immediate(%Job{failure_private: times_retried} = job, reason, %{times: max_retries}) when times_retried < max_retries do
    Logger.info "Job failed because #{inspect reason}, retrying #{max_retries - times_retried} more times, job: #{inspect job}"

    {:cont, times_retried + 1, 0}
  end
  def immediate(_, _, _), do: :halt
end
