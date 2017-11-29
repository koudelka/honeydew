defmodule Honeydew.SuccessMode.Log do
  require Logger
  alias Honeydew.Job
  @behaviour Honeydew.SuccessMode

  @impl true
  def validate_args!([]), do: :ok
  def validate_args!(args), do: raise ArgumentError, "You provided arguments (#{inspect args}) to the Log success mode, it only accepts an empty list"

  @impl true
  def handle_success(%Job{enqueued_at: enqueued_at, started_at: started_at, completed_at: completed_at} = job, []) do
    Logger.info fn ->
      queue_time = started_at - enqueued_at
      run_time = completed_at - started_at
      "Job #{inspect job} completed, sat in queue for #{queue_time}ms, and took #{run_time}ms to complete."
    end
  end
end
