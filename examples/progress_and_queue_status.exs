#
# Workers can update their current status with `Honeydew.Progress.progress/1`.
# You can view the status of all your workers with `Honeydew.status/1`.
#

#
# elixir -S mix run progress_and_queue_status.exs
#

defmodule HeavyTask do
  import Honeydew.Progress

  @behaviour Honeydew.Worker

  def work_really_hard(secs) do
    progress("Getting ready to do stuff!")
    Enum.each 0..secs, fn i ->
      Process.sleep(1000)
      progress("I've been working hard for #{i} secs!")
    end
    IO.puts "I worked really hard for #{secs} secs!"
  end
end


defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, HeavyTask, num: 10)
  end
end


App.start

{:work_really_hard, [20]} |> Honeydew.async(:my_queue)
Process.sleep(500)

#
# The :workers key maps from worker pids to their `{job, job_status}`
#
Honeydew.status(:my_queue)
|> Map.get(:workers)
|> Enum.each(fn
  {worker, nil} ->
    IO.puts "#{inspect worker} -> idle"
  {worker, {_job, status}} ->
    IO.puts "#{inspect worker} -> #{inspect status}"
end)
