defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.Worker

  def start_link(pool_name, worker_module, worker_init_args, init_retry_secs, num_workers, max_errors_per_second) do
    import Supervisor.Spec

    children = [
      worker(Worker, [pool_name, worker_module, worker_init_args, init_retry_secs], restart: :transient)
    ]


    opts = [strategy: :simple_one_for_one,
            name: Honeydew.worker_supervisor_name(worker_module, pool_name),
            max_restarts: num_workers * max_errors_per_second,
            max_seconds: 1]

    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # start up workers
    Enum.each(1..num_workers, fn(_) ->
      Supervisor.start_child(supervisor, [])
    end)

    {:ok, supervisor}
  end
end
