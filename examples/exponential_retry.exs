#
# iex -S mix run examples/exponential_retry.exs
#

defmodule Worker do
  @behaviour Honeydew.Worker

  def crash(enqueued_at) do
    secs_later = DateTime.diff(DateTime.utc_now(), enqueued_at, :millisecond) / 1_000
    IO.puts "I ran #{secs_later}s after enqueue!"
    raise "crashing on purpose!"
  end
end

defmodule App do
  alias Honeydew.FailureMode.ExponentialRetry

  def start do
    :ok = Honeydew.start_queue(:my_queue, failure_mode: {ExponentialRetry, [times: 5]})
    :ok = Honeydew.start_workers(:my_queue, Worker)
  end
end

App.start
Logger.configure(level: :error) # don't fill the console with crash reports
{:crash, [DateTime.utc_now()]} |> Honeydew.async(:my_queue, delay_secs: 1)
