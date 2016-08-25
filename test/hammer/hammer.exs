defmodule Worker do
  use Honeydew

  def init(args) do
    {:ok, args}
  end

  def echo(arg, _state) do
    arg
  end

end

defmodule Honeydew.Hammer do

  @num_jobs 1_000_000

  def run(func) do
    children = [
      Honeydew.child_spec("pool", Worker, [], num_workers: 10)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)

    {microsecs, :ok} = :timer.tc(__MODULE__, func, [])
    secs = microsecs/:math.pow(10, 6)
    IO.puts("processed #{@num_jobs} in #{secs}s -> #{@num_jobs/secs} per sec")
  end

  def call do
    Enum.map(0..@num_jobs, fn _ ->
      Task.async(fn ->
        :hi = Worker.call("pool", {:echo, [:hi]})
      end)
    end)
    |> Enum.each(&Task.await(&1, :infinity))
  end

  def cast do
    Enum.map(0..@num_jobs, fn _ ->
      Task.async(fn ->
        Worker.cast("pool", {:echo, [:hi]})
      end)
    end)

    me = self
    Worker.cast("pool", fn _ -> send me, :done end)

    receive do
      :done -> :ok
    end
  end
end

Honeydew.Hammer.run(:cast)
