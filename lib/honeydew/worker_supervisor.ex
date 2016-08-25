defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.Worker

  def start_link(queue, module, args, num_workers, init_retry_secs, shutdown) do
    import Supervisor.Spec

    children = [worker(Worker, [queue, module, args, init_retry_secs], restart: :transient, shutdown: shutdown)]

    opts = [strategy: :simple_one_for_one,
            name: Honeydew.supervisor(queue, :worker),
            max_restarts: num_workers,
            max_seconds: init_retry_secs]

    {:ok, supervisor} = Supervisor.start_link(children, opts)

    start_children(supervisor, num_workers)

    {:ok, supervisor}
  end

  defp start_children(_supervisor, 0), do: :noop
  defp start_children(supervisor, num) do
    Supervisor.start_child(supervisor, [])
    start_children(supervisor, num-1)
  end

end
