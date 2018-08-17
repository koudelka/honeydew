#
# Optionally, you can receive a response from a job with `yield/2`. To tell Honeydew that we expect a response, you must specify `reply: true`, like so:
#
# iex(1)> {:run, [1]} |> Honeydew.async(:my_queue, reply: true)
# {:ok, 2}
#
# If you pass `reply: true`, and you never call `yield/2` to read the result, your process' mailbox may fill up after multiple calls. Don't do that.

#

#
# iex -S mix run job_replies.exs
#

defmodule Worker do
  @behaviour Honeydew.Worker

  def run(num) do
    1 + num
  end
end

defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, Worker)
  end
end

App.start
job = {:run, [1]} |> Honeydew.async(:my_queue, reply: true)
job |> Honeydew.yield |> IO.inspect
