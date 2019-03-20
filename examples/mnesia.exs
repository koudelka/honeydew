#
# iex -S mix run examples/mnesia.exs
#

defmodule Worker do
  @behaviour Honeydew.Worker

  def hello(thing) do
    IO.puts "Hello #{thing}!"
  end
end

defmodule App do
  def start do
    nodes = [node()]
    :ok = Honeydew.start_queue(:my_queue, queue: {Honeydew.Queue.Mnesia, [disc_copies: nodes]})
    :ok = Honeydew.start_workers(:my_queue, Worker)
  end
end

App.start
{:hello, ["World"]} |> Honeydew.async(:my_queue)
