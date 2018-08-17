#
# elixir -S mix run initialized_worker.exs
#

defmodule Database do
  def connect(ip, port) do
    {:ok, "connection to #{ip}:#{port}"}
  end

  def find(id, db) do
    IO.puts "finding #{id} in db #{inspect db}"
    %{id: id, name: "koudelka", email: "koudelka+honeydew@ryoukai.org"}
  end
end

defmodule Worker do
  @behaviour Honeydew.Worker

  def init([ip, port]) do
    {:ok, db} = Database.connect(ip, port)
    {:ok, db}
  end

  def send_email(id, db) do
    %{name: name, email: email} = Database.find(id, db)

    IO.puts "sending email to #{email}"
    IO.inspect "hello #{name}, want to enlarge ur keyboard by 500%???"
  end
end

defmodule App do
  def start do
    :ok = Honeydew.start_queue(:my_queue)
    :ok = Honeydew.start_workers(:my_queue, {Worker, ["database.host", 1234]})
  end
end

App.start
{:send_email, ["2145"]} |> Honeydew.async(:my_queue)
Process.sleep(100)
