defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.Worker

  def start_link(queue, %{shutdown: shutdown, init_retry: init_retry_secs, num: num} = opts, queue_pid) do
    import Supervisor.Spec

    children = [worker(Worker, [queue, opts, queue_pid], restart: :transient, shutdown: shutdown)]

    supervisor_opts = [
      strategy: :simple_one_for_one,
      name: Honeydew.supervisor(queue, :worker),
      max_restarts: num,
      max_seconds: init_retry_secs
    ]

    {:ok, supervisor} = Supervisor.start_link(children, supervisor_opts)

    start_workers(supervisor, num)

    {:ok, supervisor}
  end

  defp start_workers(_supervisor, 0), do: :noop

  defp start_workers(supervisor, num) do
    Supervisor.start_child(supervisor, [])
    start_workers(supervisor, num - 1)
  end
end
