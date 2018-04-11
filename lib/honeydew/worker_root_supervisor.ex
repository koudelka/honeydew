defmodule Honeydew.WorkerRootSupervisor do
  alias Honeydew.{WorkerGroupsSupervisor, WorkerStarter}

  def start_link(queue, %{nodes: nodes} = opts) do
    import Supervisor.Spec

    Honeydew.create_groups(queue)

    children = [supervisor(WorkerGroupsSupervisor, [queue, opts]),
                worker(WorkerStarter, [queue])]

    # if the worker groups supervisor shuts down due to too many groups
    # restarting (hits max intensity), we also want the WorkerStarter to die
    # so that it may restart the necessary worker groups when the groups
    # supervisor comes back up
    supervisor_opts = [strategy: :rest_for_one,
                       name: Honeydew.supervisor(queue, :worker_root)]

    queue
    |> case do
         {:global, _} -> children ++ [supervisor(Honeydew.NodeMonitorSupervisor, [queue, nodes])]
         _ -> children
       end
    |> Supervisor.start_link(supervisor_opts)
  end
end
