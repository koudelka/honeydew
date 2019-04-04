#
# iex -S mix run examples/delayed_job.exs
#

defmodule Worker do
  @behaviour Honeydew.Worker

  def hello(enqueued_at) do
    secs_later = DateTime.diff(DateTime.utc_now(), enqueued_at, :millisecond) / 1_000
    IO.puts "I was delayed by #{secs_later}s!"
  end
end

defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, Worker)
  end
end

App.start
{:hello, [DateTime.utc_now()]} |> Honeydew.async(:my_queue, delay_secs: 2)
