defmodule Honeydew.WorkerGroupsSupervisor do
  use DynamicSupervisor
  alias Honeydew.WorkerGroupSupervisor

  def start_link([queue, _] = extra_args) do
    supervisor_opts = [name: Honeydew.supervisor(queue, :worker_groups)]

    DynamicSupervisor.start_link(__MODULE__, extra_args, supervisor_opts)
  end

  def start_group(queue, queue_pid) do
    queue
    |> Honeydew.supervisor(:worker_groups)
    |> DynamicSupervisor.start_child({WorkerGroupSupervisor, queue_pid})
  end

  @impl true
  def init(extra_args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: extra_args)
  end
end
