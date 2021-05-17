defmodule Honeydew.WorkerGroupSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Honeydew.WorkersPerQueueSupervisor
  alias Honeydew.Processes

  def start_link([queue, opts]) do
    DynamicSupervisor.start_link(__MODULE__, [queue, opts], name: Processes.process(queue, __MODULE__))
  end

  def init(extra_args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: extra_args)
  end

  def start_worker_group(queue, queue_pid) do
    queue
    |> Processes.process(__MODULE__)
    |> DynamicSupervisor.start_child({WorkersPerQueueSupervisor, queue_pid})
  end
end
