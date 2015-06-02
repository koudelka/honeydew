defmodule Honeydew.Supervisor do

  def start_link(pool_name, worker_module, worker_init_args, pool_opts \\ []) do
    import Supervisor.Spec

    max_failures       = pool_opts[:max_failures] || 3
    failure_delay_secs = pool_opts[:failure_delay_secs] || 30

    num_workers     = pool_opts[:workers] || 10
    init_retry_secs = pool_opts[:init_retry_secs] || 5

    work_queue_name = Honeydew.work_queue_name(worker_module, pool_name)

    children = [
      worker(Honeydew.WorkQueue, [work_queue_name, max_failures, failure_delay_secs], id: :work_queue),
      supervisor(Honeydew.WorkerSupervisor, [], id: :worker_supervisor)
    ]

    {:ok, supervisor} = Supervisor.start_link(children, strategy: :rest_for_one)

    # start up workers
    [{:worker_supervisor, worker_supervisor, _, _},
     {:work_queue, work_queue, _, _}] = Supervisor.which_children(supervisor)

    Enum.each(1..num_workers, fn(_) ->
      Supervisor.start_child(worker_supervisor, [work_queue, worker_module, worker_init_args, init_retry_secs])
    end)

    {:ok, supervisor}
  end
end
