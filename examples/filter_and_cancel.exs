#
# If a job hasn't been started yet, you can cancel it with `Honeydew.cancel/1`
#
# If you don't already have the job struct, you can find it by passing a function to `Honeydew.filter/2`
#

defmodule Worker do
  @behaviour Honeydew.Worker

  def run(i) do
    Process.sleep(10_000)
    IO.puts "job #{i} finished"
  end
end

defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, Worker, num: 10)
  end
end


App.start

# enqueue eleven jobs
Enum.each(0..10, & {:run, [&1]} |> Honeydew.async(:my_queue))

# Status indicates that eleven jobs are queued
Honeydew.status(:my_queue)
|> Map.get(:queue)
|> IO.inspect

# find the job that would run with the argument `10`, as it won't have started yet
# and cancel it
:ok =
  Honeydew.filter(:my_queue, %{task: {:run, [10]}})
  |> List.first
  |> Honeydew.cancel

# You should see that there are only ten jobs enqueued now.
Honeydew.status(:my_queue)
|> Map.get(:queue)
|> IO.inspect
