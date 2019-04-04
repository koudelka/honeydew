defmodule Honeydew.FailureMode.ExponentialRetry do
  alias Honeydew.Job
  alias Honeydew.FailureMode.Retry
  alias Honeydew.FailureMode.Move

  @moduledoc """
  Instructs Honeydew to retry a job a number of times on failure, waiting an exponentially growing number
  of seconds between retry attempts. You may specify the base of exponential delay with the `:base` argument,
  it defaults to 2.

  Please note, this failure mode will not work with the ErlangQueue queue implementation at the moment.

  ## Examples

  Retry jobs in this queue 3 times, delaying exponentially between with a base of 2:

  ```elixir
  Honeydew.start_queue(:my_queue, failure_mode: {#{inspect __MODULE__},
                                                 times: 3,
                                                 base: 2})
  ```

  Retry jobs in this queue 3 times, delaying exponentially between with a base of 2, and then move to another queue:

  ```elixir
  Honeydew.start_queue(:my_queue,
                       failure_mode: {#{inspect __MODULE__},
                                      times: 3,
                                      base: 2,
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
    |> validate_args!
  end

  def validate_args!(%{base: base}) when not is_integer(base) or base <= 0 do
    raise ArgumentError, "You provided a bad `:base` argument (#{inspect base}) to the ExponentialRetry failure mode, it's expecting a positive number."
  end

  def validate_args!(args), do: Retry.validate_args!(args, __MODULE__)

  @impl true
  def handle_failure(job, reason, args) do
    args =
      args
      |> Keyword.put(:fun, &exponential/3)
      |> Keyword.put_new(:base, 2)

    Retry.handle_failure(job, reason, args)
  end

  #
  # base ^ times_retried - 1, rounded to integer
  #

  def exponential(%Job{failure_private: nil} = job, reason, args) do
    exponential(%Job{job | failure_private: 0}, reason, args)
  end

  def exponential(%Job{failure_private: times_retried} = job, reason, %{times: max_retries, base: base}) when times_retried < max_retries do
    delay_secs = (:math.pow(base, times_retried) - 1) |> round()

    Logger.info "Job failed because #{inspect reason}, retrying #{max_retries - times_retried} more times, next attempt in #{delay_secs}s, job: #{inspect job}"

    {:cont, times_retried + 1, delay_secs}
  end
  def exponential(_, _, _), do: :halt
end
