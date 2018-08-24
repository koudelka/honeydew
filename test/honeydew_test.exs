defmodule HoneydewTest do
  use ExUnit.Case, async: false
  import Helper
  alias Honeydew.Job
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.Workers

  @moduletag :capture_log

  setup :restart_honeydew

  test "queues/0 + stop_queue/1" do
    assert Enum.empty?(Honeydew.queues)

    :ok = Honeydew.start_queue(:a_queue)
    :ok = Honeydew.start_queue(:another_queue)
    :ok = Honeydew.start_queue({:global, :a_global_queue})

    assert Honeydew.queues() == [:a_queue, :another_queue, {:global, :a_global_queue}]

    :ok = Honeydew.stop_queue({:global, :a_global_queue})

    assert Honeydew.queues() == [:a_queue, :another_queue]
  end

  test "workers/0 + stop_workers/1" do
    assert Enum.empty?(Honeydew.workers)

    :ok = Honeydew.start_workers(:a_queue, Stateless)
    :ok = Honeydew.start_workers(:another_queue, Stateless)
    :ok = Honeydew.start_workers({:global, :a_global_queue}, Stateless)

    assert Honeydew.workers() == [:a_queue, :another_queue, {:global, :a_global_queue}]

    :ok = Honeydew.stop_workers({:global, :a_global_queue})

    assert Honeydew.workers() == [:a_queue, :another_queue]
  end

  test "group/1" do
    assert Honeydew.group(:my_queue, Workers) == :"Elixir.Honeydew.Workers.my_queue"
  end

  describe "process/2" do
    test "local" do
      assert Honeydew.process(:my_queue, WorkerGroupSupervisor) == :"Elixir.Honeydew.WorkerGroupSupervisor.my_queue"
    end

    test "global" do
      assert Honeydew.process({:global, :my_queue}, WorkerGroupSupervisor) == :"Elixir.Honeydew.WorkerGroupSupervisor.global.my_queue"
    end
  end

  test "table_name/1" do
    assert Honeydew.table_name({:global, :my_queue}) == "global_my_queue"
    assert Honeydew.table_name(:my_queue) == "my_queue"
  end

  test "success mode smoke test" do
    queue = :erlang.unique_integer
    :ok = Honeydew.start_queue(queue, success_mode: {TestSuccessMode, [to: self()]})
    :ok = Honeydew.start_workers(queue, Stateless)

    %Job{private: id} = fn -> :noop end |> Honeydew.async(queue)

    assert_receive %Job{private: ^id}
  end

  test "progress updates" do
    queue = :erlang.unique_integer
    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless)

    {:emit_progress, ["doing thing 1/2"]} |> Honeydew.async(queue)

    Process.sleep(100)

    [{_worker, {_job, status}}] =
      queue
      |> Honeydew.status
      |> Map.get(:workers)
      |> Enum.filter(fn {_pid, {_job, _status}} -> true
                                              _ -> false end)

    assert status == {:running, "doing thing 1/2"}
  end

  test "remains operational during chaos" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless, num: 5)

    queue_pid = Honeydew.get_queue(queue)

    Honeydew.suspend(queue)
    Enum.each(0..200, fn _ ->
      # different kinds of failing jobs
      fn -> raise "intentional crash" end |> Honeydew.async(queue)
      fn -> throw "intentional crash" end |> Honeydew.async(queue)
      # unhandled messages
      fn -> send self(), :rubbish end |> Honeydew.async(queue)
    end)
    me = self()
    fn -> send(me, :still_here) end |> Honeydew.async(queue)
    Honeydew.resume(queue)

    receive do
      :still_here ->
        Process.sleep(50) # let remaining jobs fail so :capture_log can dispose of their logs
        :ok
    end

    assert queue_pid == Honeydew.get_queue(queue)
  end

  test "workers don't restart after a successful job" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn -> :ok end |> Honeydew.async(queue)
    Process.sleep(100)

    assert [worker] == workers(queue)
  end

  test "workers don't restart when a linked process terminates normally" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn -> spawn_link(fn -> :ok end); Process.sleep(100) end |> Honeydew.async(queue)
    Process.sleep(200)

    assert [worker] == workers(queue)
  end

  test "workers restart when a linked process terminates abnormally" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn -> spawn_link(fn -> raise "intentional crash" end) end |> Honeydew.async(queue)
    Process.sleep(200)

    assert [worker] != workers(queue)
  end

  test "workers restart after a job crashes" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn -> raise "intentional crash" end |> Honeydew.async(queue)
    Process.sleep(100)

    [new_worker] = workers(queue)

    assert worker != new_worker
  end

  test "stateful workers reinitialize by default" do
    queue = :erlang.unique_integer
    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, {FailInitOnceWorker, self()}, num: 1, init_retry_secs: 1)

    assert_receive :init_ran
    Process.sleep(1_000)
    assert_receive :init_ran
  end

  test "stateful workers don't take work until their module init succeeds" do
    queue = :erlang.unique_integer
    test_process = self()

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, {FailedInitWorker, test_process}, num: 1)

    fn _ -> send test_process, :job_ran end |> Honeydew.async(queue)

    receive do
      {:init, worker} -> send worker, :raise
    end
    assert_receive :failed_init_ran
    refute_receive :job_ran

    receive do
      {:init, worker} -> send worker, :throw
    end
    assert_receive :failed_init_ran
    refute_receive :job_ran

    receive do
      {:init, worker} -> send worker, :ok
    end
    assert_receive :job_ran
  end

  defp workers(queue) do
    Honeydew.status(queue) |> Map.get(:workers) |> Map.keys
  end
end
