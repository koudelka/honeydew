#
# iex -S mix run local.exs
#

defmodule Worker do
  @behaviour Honeydew.Worker

  def hello(thing) do
    IO.puts "Hello #{thing}!"
  end
end

defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, Worker)
  end
end

App.start
{:hello, ["World"]} |> Honeydew.async(:my_queue)
