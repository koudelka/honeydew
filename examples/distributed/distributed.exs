defmodule HeavyTask do
  @behaviour Honeydew.Worker

  # note that in this case, our worker is stateless, so we left out `init/1`

  def work_really_hard(secs) do
    :timer.sleep(1_000 * secs)
    IO.puts "I worked really hard for #{secs} secs!"
  end
end

defmodule QueueApp do
  def start do
    nodes = [node()]
    :ok = Honeydew.start_queue({:global, :my_queue}, queue: {Honeydew.Queue.Mnesia, [nodes, [disc_copies: nodes], []]})
  end
end

defmodule WorkerApp do
  def start do
    #
    # change me!
    #
    nodes = [:clientfacing@dax, :queue@dax]
    :ok = Honeydew.start_workers({:global, :my_queue}, HeavyTask, num: 10, nodes: nodes)
  end
end

#
# iex --sname queue -S mix run examples/distributed/distributed.exs
#
# iex --sname worker -S mix run examples/distributed/distributed.exs
#
# iex --sname clientfacing -S mix run examples/distributed/distributed.exs
#
