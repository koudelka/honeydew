#
# Workers can update their current status with `Honeydew.Progress.progress/1`.
# You can view the status of all your workers with `Honeydew.status/1`.
#

# App.start
# job = {:work_really_hard, [20]} |> Honeydew.async(:my_queue)
# Honeydew.status(:my_queue)

defmodule HeavyTask do
  import Honeydew.Progress

  @behaviour Honeydew.Worker

  def work_really_hard(secs) do
    Enum.each 0..secs, fn i ->
      Process.sleep(1_000)
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
