defmodule Honeydew.WorkerGroupsSupervisor do
  alias Honeydew.WorkerGroupSupervisor

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts},
      type: :supervisor
    }
  end

  def start_link(queue, opts) do
    supervisor_opts = [strategy: :one_for_one,
                       name: Honeydew.supervisor(queue, :worker_groups),
                       extra_arguments: [queue, opts]]

    DynamicSupervisor.start_link(supervisor_opts)
  end

  def start_group(supervisor, queue_pid) do
    {:ok, _group} = DynamicSupervisor.start_child(supervisor, {WorkerGroupSupervisor, [queue_pid]})
  end
end
