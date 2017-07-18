# App.start
# {:work_really_hard, [10]} |> Honeydew.async(:my_queue)
# Honeydew.status(:my_queue)

defmodule HeavyTask do
  use Honeydew.Progress

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
    children = [
      Honeydew.queue_spec(:my_queue),
      Honeydew.worker_spec(:my_queue, HeavyTask, num: 10)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
