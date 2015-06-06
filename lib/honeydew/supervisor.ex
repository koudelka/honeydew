defmodule Honeydew.Supervisor do

  def start_link(pool_name, worker_module, worker_init_args, pool_opts \\ []) do
    import Supervisor.Spec

    max_failures       = pool_opts[:max_failures] || 3
    failure_delay_secs = pool_opts[:failure_delay_secs] || 30

    num_workers     = pool_opts[:workers] || 10
    init_retry_secs = pool_opts[:init_retry_secs] || 5

    work_queue = Honeydew.work_queue_name(worker_module, pool_name)
    worker_supervisor = Honeydew.worker_supervisor_name(worker_module, pool_name)

    children = [
      worker(Honeydew.WorkQueue, [work_queue, max_failures, failure_delay_secs], id: :work_queue),
      supervisor(Honeydew.WorkerSupervisor, [pool_name, worker_module, worker_init_args, init_retry_secs, num_workers], id: :worker_supervisor)
    ]

    Supervisor.start_link(children, strategy: :rest_for_one)
  end
end
