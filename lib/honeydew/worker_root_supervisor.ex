defmodule Honeydew.WorkerRootSupervisor do
  alias Honeydew.{WorkerGroupsSupervisor, WorkerStarter}

  def start_link(queue, %{nodes: nodes} = opts) do
    import Supervisor.Spec

    children = [supervisor(WorkerGroupsSupervisor, [queue, opts]),
                worker(WorkerStarter, [queue])]

    supervisor_opts = [strategy: :one_for_one,
                       name: Honeydew.supervisor(queue, :worker_root)]

    queue
    |> case do
         {:global, _} -> children ++ [supervisor(Honeydew.NodeMonitorSupervisor, [queue, nodes])]
         _ -> children
       end
    |> Supervisor.start_link(supervisor_opts)
  end
end
