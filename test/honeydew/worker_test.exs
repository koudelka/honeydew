defmodule Honeydew.WorkerTest do
  use ExUnit.Case, async: true

  setup [:setup_queue_name, :setup_queue, :setup_worker_pool]


  test "workers should die when their queue dies", %{queue: queue} do
    queue_pid = Honeydew.get_queue(queue)
    %{workers: workers} = Honeydew.status(queue)

    Process.exit(queue_pid, :kill)

    Process.sleep(100)

    workers
    |> Map.keys
    |> Enum.each(fn w -> assert not Process.alive?(w) end)
  end


  defp setup_queue_name(_), do: {:ok, [queue: generate_queue_name()]}

  defp setup_queue(%{queue: queue}) do
    {:ok, queue_sup} = start_queue(queue)
    [{_, queue_sup, _, _}] = Supervisor.which_children(queue_sup)
    {:ok, [queue_sup: queue_sup]}
  end

  defp setup_worker_pool(%{queue: queue}) do
    {:ok, worker_sup} = start_worker_pool(queue)
    [{_, worker_sup, _, _}] = Supervisor.which_children(worker_sup)
    {:ok, [worker_sup: worker_sup]}
  end

  defp generate_queue_name do
    "#{:erlang.monotonic_time()}_#{:erlang.unique_integer()}"
  end

  defp start_queue(queue, opts \\ []) do
    queue_opts = Keyword.merge([queue: Honeydew.Queue.ErlangQueue], opts)
    Helper.start_queue_link(queue, queue_opts)
  end

  defp start_worker_pool(queue) do
    Helper.start_worker_link(queue, Stateless)
  end
end
