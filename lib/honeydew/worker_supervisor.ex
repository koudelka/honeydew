defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.Worker

  def start_link(queue, module, args, num_workers, init_retry_secs, shutdown) do
    import Supervisor.Spec

    children = Enum.map(1..num_workers, fn n ->
      worker(Worker,[queue, module, args, init_retry_secs], id: "#{module}##{n}", restart: :transient, shutdown: shutdown)
    end)

    opts = [strategy: :one_for_one,
            name: Honeydew.supervisor(queue, :worker),
            max_restarts: num_workers,
            max_seconds: init_retry_secs]

    Supervisor.start_link(children, opts)
  end
end
