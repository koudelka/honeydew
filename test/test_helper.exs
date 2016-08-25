defmodule Stateless do
  def send_msg(to, msg) do
    send(to, msg)
  end

  def return(term) do
    term
  end

  def sleep(time) do
    Process.sleep(time)
  end

  def crash(pid) do
    send pid, :job_ran
    raise "ignore this crash"
  end
end

defmodule Stateful do
  def init(state) do
    {:ok, state}
  end

  def send_msg(to, msg, state) do
    send(to, {msg, state})
  end

  def return(term, state) do
    {term, state}
  end
end

defmodule Helper do
  def start_queue_link(queue, opts \\ []) do
    Supervisor.start_link([Honeydew.queue_spec(queue, opts)], strategy: :one_for_one)
  end

  def start_worker_link(queue, module, opts \\ []) do
    Supervisor.start_link([Honeydew.worker_spec(queue, module, opts)], strategy: :one_for_one)
  end

  def stop(queue) do
    queue
    |> Honeydew.supervisor(:root)
    |> Supervisor.stop
  end
end

# defmodule BadInit do
#   def init(_) do
#     :bad
#   end
# end

# defmodule RaiseOnInit do
#   def init(_) do
#     raise "bad"
#   end
# end

# defmodule LinkDiesOnInit do
#   def init(_) do
#     spawn_link fn -> :born_to_die end
#   end
# end

ExUnit.start()
