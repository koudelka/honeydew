defmodule Honeydew.MnesiaQueueIntegrationTest do
  use ExUnit.Case, async: true
  alias Honeydew.Job

  @moduletag :capture_log

  @num_workers 5

  setup do
    queue = "#{:erlang.monotonic_time}_#{:erlang.unique_integer}"
    nodes = [node()]
    {:ok, queue_sup} = Helper.start_queue_link(queue, queue: {Honeydew.Queue.Mnesia, [nodes, [disc_copies: nodes], []]})
    {:ok, worker_sup} = Helper.start_worker_link(queue, Stateless, num: @num_workers)

    [queue: queue, queue_sup: queue_sup, worker_sup: worker_sup]
  end

  test "async/3", %{queue: queue} do
    %Job{} = {:send_msg, [self(), :hi]} |> Honeydew.async(queue)
    assert_receive :hi
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

  test "filter/1 supports :mnesia.match_object/1", %{queue: queue} do
    Honeydew.suspend(queue)

    {:sleep, [1_000]} |> Honeydew.async(queue)
    {:sleep, [2_000]} |> Honeydew.async(queue)
    {:sleep, [2_000]} |> Honeydew.async(queue)
    Enum.each(1..3, fn i -> {:send_msg, [self(), i]} |> Honeydew.async(queue) end)

    jobs = Honeydew.filter(queue, %{task: {:sleep, [2_000]}})
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
        Process.sleep(50)
        send(me, :hi)
      end
      |> Honeydew.async(queue)
      |> Honeydew.cancel

    assert_receive :hi
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

  test "resets in-progress jobs after crashing", %{queue: queue, queue_sup: queue_sup, worker_sup: worker_sup} do
    Enum.each(1..10, fn _ ->
      Honeydew.async(fn -> Process.sleep(20_000) end, queue)
    end)

    %{queue: %{count: total, in_progress: in_progress}, workers: workers} = Honeydew.status(queue)

    assert total == 10
    assert in_progress == @num_workers

    queue_process = Honeydew.get_queue(queue)

    Process.flag(:trap_exit, true)

    Process.exit(queue_sup, :normal)
    Process.sleep(500)
    assert not Process.alive?(queue_process)
    assert nil == Honeydew.get_queue(queue)

    Process.exit(worker_sup, :kill)

    workers
    |> Map.keys
    |> Enum.each(fn worker ->
      Process.exit(worker, :kill)
      assert not Process.alive?(worker)
    end)

    Process.flag(:trap_exit, false)

    nodes = [node()]
    {:ok, _} = Helper.start_queue_link(queue, queue: {Honeydew.Queue.Mnesia, [nodes, [disc_copies: nodes], []]})

    %{queue: %{count: total, in_progress: in_progress}} = Honeydew.status(queue)

    assert total == 10
    assert in_progress == 0
  end
end
