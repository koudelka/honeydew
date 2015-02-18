defmodule Honeydew.HomeSupervisor do

  def start_link(honey_module, honey_init_args, pool_opts) do
    import Supervisor.Spec

    children = [
      worker(Honeydew.JobList, [honey_module, pool_opts[:max_failures] || 3, pool_opts[:delay_secs] || 30]),
      supervisor(Honeydew.HoneySupervisor, [honey_module, honey_init_args, pool_opts[:workers] || 10, pool_opts[:init_retry_secs] || 5])
    ]

    opts = [strategy: :rest_for_one, name: Honeydew.home_supervisor(honey_module)]

    Supervisor.start_link(children, opts)
  end
end
