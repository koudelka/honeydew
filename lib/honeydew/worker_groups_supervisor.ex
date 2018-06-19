defmodule Honeydew.WorkerGroupsSupervisor do
  alias Honeydew.WorkerGroupSupervisor

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts}
    }
  end

  def start_link(queue, opts) do
    children = [{WorkerGroupSupervisor, [queue, opts]}]

    supervisor_opts = [strategy: :simple_one_for_one,
                       name: Honeydew.supervisor(queue, :worker_groups)]

    Supervisor.start_link(children, supervisor_opts)
  end

  def start_group(supervisor, queue_pid) do
    {:ok, _group} = Supervisor.start_child(supervisor, [queue_pid])
  end
end
