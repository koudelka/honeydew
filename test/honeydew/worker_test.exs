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

  defp setup_queue_name(%{queue: queue}), do: {:ok, [queue: queue]}
  defp setup_queue_name(_), do: {:ok, [queue: generate_queue_name()]}

  defp setup_queue(%{queue: queue}) do
    :ok = Honeydew.start_queue(queue)
  end

  defp setup_worker_pool(%{queue: queue}) do
    :ok = Honeydew.start_workers(queue, Stateless, num: 10)
  end

  defp generate_queue_name do
    "#{:erlang.monotonic_time}_#{:erlang.unique_integer}"
  end
end
