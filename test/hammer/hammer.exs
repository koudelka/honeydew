defmodule Worker do
  def thing do
    :hi
  end

  # def send(to, msg) do
  #   send to, msg
  # end
end

defmodule Honeydew.Hammer do

  @num_jobs 5_00_000

  def run(func) do
    :ok = Honeydew.start_queue(:queue)
    :ok = Honeydew.start_workers(:queue, Worker, num_workers: 10)

    {microsecs, :ok} = :timer.tc(__MODULE__, func, [])
    secs = microsecs/:math.pow(10, 6)
    IO.puts("processed #{@num_jobs} in #{secs}s -> #{@num_jobs/secs} per sec")
  end

  def reply do
    Enum.map(1..@num_jobs, fn _ ->
      Task.async(fn ->
        {:ok, :hi} = Honeydew.async({:thing, []}, :queue, reply: true) |> Honeydew.yield(20_000)
      end)
    end)
    |> Enum.each(&Task.await(&1, :infinity))
  end

  def no_reply do
    Enum.each(1..@num_jobs, fn _ ->
      Task.async(fn ->
        Honeydew.async(:thing, :queue)
      end)
    end)

    me = self()
    Honeydew.async(fn -> send me, :done end, :queue)

    receive do
      :done -> :ok
    end
  end
end

Honeydew.Hammer.run(:no_reply)
