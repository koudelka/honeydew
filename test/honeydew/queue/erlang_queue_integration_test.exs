defmodule Honeydew.ErlangQueueIntegrationTest do
  use ExUnit.Case, async: true
  alias Honeydew.Job

  setup [:generate_queue_name, :start_queue, :start_worker_pool]

  test "async/3", %{queue: queue} do
    %Job{} = {:send_msg, [self(), :hi]} |> Honeydew.async(queue)

    assert_receive :hi
  end

  @tag :skip_worker_pool
  test "async/3 when queue doesn't exist" do
    assert_raise RuntimeError, fn ->
      Honeydew.async({:send_msg, [self(), :hi]}, :nonexistent_queue)
    end
  end

  test "yield/2", %{queue: queue} do
    first_job  = {:return, [:hi]} |> Honeydew.async(queue, reply: true)
    second_job = {:return, [:there]} |> Honeydew.async(queue, reply: true)

    assert {:ok, :hi}    = Honeydew.yield(first_job)
    assert {:ok, :there} = Honeydew.yield(second_job)
  end

  test "suspend/1", %{queue: queue} do
    Honeydew.suspend(queue)
    {:send_msg, [self(), :hi]} |> Honeydew.async(queue)
    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 1
    assert Honeydew.status(queue) |> get_in([:queue, :suspended]) == true
    refute_receive :hi
  end

  test "resume/1", %{queue: queue} do
    Honeydew.suspend(queue)
    {:send_msg, [self(), :hi]} |> Honeydew.async(queue)
    refute_receive :hi
    Honeydew.resume(queue)
    assert_receive :hi
    assert Honeydew.status(queue) |> get_in([:queue, :suspended]) == false
  end

  test "status/1", %{queue: queue} do
    {:sleep, [1_000]} |> Honeydew.async(queue)
    Honeydew.suspend(queue)
    Enum.each(1..3, fn _ -> {:send_msg, [self(), :hi]} |> Honeydew.async(queue) end)
    Process.sleep(200) # let monitors send acks
    assert %{queue: %{count: 4, in_progress: 1, suspended: true}} = Honeydew.status(queue)
  end

  test "filter/1", %{queue: queue} do
    Honeydew.suspend(queue)

    {:sleep, [1_000]} |> Honeydew.async(queue)
    {:sleep, [2_000]} |> Honeydew.async(queue)
    {:sleep, [2_000]} |> Honeydew.async(queue)
    Enum.each(1..3, fn i -> {:send_msg, [self(), i]} |> Honeydew.async(queue) end)

    jobs = Honeydew.filter(queue, fn %Job{task: {:sleep, [2_000]}} -> true
                                                                   _ -> false end)
    assert Enum.count(jobs) == 2

    Enum.each(jobs, fn job ->
      assert Map.get(job, :task) == {:sleep, [2_000]}
    end)
  end

  test "cancel/1 when job hasn't executed", %{queue: queue} do
    Honeydew.suspend(queue)

    assert :ok =
      {:send_msg, [self(), :hi]}
      |> Honeydew.async(queue)
      |> Honeydew.cancel

    Honeydew.resume(queue)

    refute_receive :hi
  end

  test "cancel/1 when job is in progress", %{queue: queue} do
    me = self()
    assert {:error, :in_progress} =
      fn ->
        send(me, :hi)
      end
      |> Honeydew.async(queue)
      |> Honeydew.cancel

    assert_receive :hi
  end

  test "cancel/1 when has been processed", %{queue: queue} do
    job = Honeydew.async({:send_msg, [self(), :hi]}, queue)
    receive do
      :hi -> :ok
    end
    Process.sleep(100) # Wait for job to be acked

    assert {:error, :not_found} = Honeydew.cancel(job)
  end

  test "pause queue, enqueue many, filter and cancel some, resume queue", %{queue: queue} do
    Honeydew.suspend(queue)

    Enum.each(0..10, &Honeydew.async({:send_msg, [self(), &1]}, queue))

    Honeydew.filter(queue, fn job ->
      {:send_msg, [_, i]} = job.task
      rem(i, 2) == 0
    end)
    |> Enum.each(&Honeydew.cancel(&1))

    Honeydew.resume(queue)

    Enum.each([0, 2, 4, 6, 8, 10], fn i ->
      refute_receive ^i
    end)

    Enum.each([1, 3, 5, 7, 9], fn i ->
      assert_receive ^i
    end)
  end

  test "should not leak monitors", %{queue: queue} do
    queue_process = Honeydew.get_queue(queue)

    Enum.each(0..500, fn _ ->
      me = self()
      fn -> send(me, :hi) end |> Honeydew.async(queue)
      assert_receive :hi
    end)

    {:monitors, monitors} = :erlang.process_info(queue_process, :monitors)
    assert Enum.count(monitors) < 20
  end

  @tag :skip_worker_pool
  test "when workers join a queue with existing jobs", %{queue: queue} do
    %Job{} = {:send_msg, [self(), :hi]} |> Honeydew.async(queue)

    start_worker_pool(%{queue: queue})

    assert_receive :hi
  end

  @tag :skip_worker_pool
  test "when workers join a suspended queue with existing jobs", %{queue: queue} do
    %Job{} = {:send_msg, [self(), :hi]} |> Honeydew.async(queue)
    Honeydew.suspend(queue)

    start_worker_pool(%{queue: queue})

    refute_receive :hi
  end

  @tag :skip_worker_pool
  test "when workers join a suspended queue with existing jobs and queue is resumed", %{queue: queue} do
    %Job{} = {:send_msg, [self(), :hi]} |> Honeydew.async(queue)
    Honeydew.suspend(queue)

    start_worker_pool(%{queue: queue})
    refute_receive :hi

    Honeydew.resume(queue)

    assert_receive :hi
  end

  defp generate_queue_name(%{queue: queue}), do: {:ok, [queue: queue]}
  defp generate_queue_name(_) do
    queue = "#{:erlang.monotonic_time}_#{:erlang.unique_integer}"
    {:ok, [queue: queue]}
  end

  defp start_queue(%{queue: queue}) do
    {:ok, queue_sup} = Helper.start_queue_link(queue, queue: Honeydew.Queue.ErlangQueue)

    {:ok, [queue_sup: queue_sup]}
  end

  defp start_worker_pool(%{skip_worker_pool: true}), do: :ok
  defp start_worker_pool(%{queue: queue}) do
    {:ok, worker_sup} = Helper.start_worker_link(queue, Stateless)
    {:ok, [worker_sup: worker_sup]}
  end
end
