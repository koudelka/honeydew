defmodule Honeydew.Processes do
  @moduledoc false

  alias Honeydew.ProcessGroupScopeSupervisor
  alias Honeydew.Queues
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.WorkerStarter
  alias Honeydew.Workers

  @processes [WorkerGroupSupervisor, WorkerStarter]

  for process <- @processes do
    def process(queue, unquote(process)) do
      name(queue, unquote(process))
    end
  end

  def start_process_group_scope(queue) do
    queue
    |> scope()
    |> ProcessGroupScopeSupervisor.start_scope()
    |> case do
         {:ok, _pid} ->
           :ok

         {:error, {:already_started, _pid}} ->
           :ok
       end
  end

  def join_group(component, queue, pid) do
    queue
    |> scope()
    |> :pg.join(component, pid)
  end

  #
  # this function may be in a hot path, so we don't call Processes.start_process_group/1 unless necessary
  #
  def get_queue(queue) do
    case get_queues(queue) do
      [queue_process | _rest] ->
        queue_process

      [] ->
        start_process_group_scope(queue)

        case get_queues(queue) do
          [queue_process | _rest] ->
            queue_process

          [] ->
            raise RuntimeError, Honeydew.no_queues_running_error(queue)
        end
    end
  end

  def get_queues(queue) do
    get_members(queue, Queues)
  end

  def get_workers(queue) do
    get_members(queue, Workers)
  end

  def get_local_members(queue, group) do
    queue
    |> scope()
    |> :pg.get_local_members(group)
  end

  defp get_members({:global, _} = queue, group) do
    queue
    |> scope()
    |> :pg.get_members(group)
  end

  defp get_members(queue, name) do
    get_local_members(queue, name)
  end

  defp scope(queue) do
    name(queue, "scope")
  end

  defp name({:global, queue}, component) do
    name([:global, queue], component)
  end

  defp name(queue, component) do
    [component, queue]
    |> List.flatten()
    |> Enum.join(".")
    |> String.to_atom()
  end
end
