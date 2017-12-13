defmodule Stateless do
  @behaviour Honeydew.Worker
  use Honeydew.Progress

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

  def emit_progress(update) do
    progress(update)
    Process.sleep(500)
  end
end

defmodule DocTestWorker do
  def ping(_ip) do
    Process.sleep(1000)
    :pong
  end
end

defmodule Stateful do
  @behaviour Honeydew.Worker
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

defmodule TestSuccessMode do
  @behaviour Honeydew.SuccessMode

  @impl true
  def validate_args!(to: to) when is_pid(to), do: :ok

  @impl true
  def handle_success(job, [to: to]) do
    send to, job
  end
end

defmodule Helper do
  def start_queue_link(queue, opts \\ []) do
    Supervisor.start_link([Honeydew.queue_spec(queue, opts)], strategy: :one_for_one, restart: :transient)
  end

  def start_worker_link(queue, module, opts \\ []) do
    Supervisor.start_link([Honeydew.worker_spec(queue, module, opts)], strategy: :one_for_one, restart: :transient)
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
