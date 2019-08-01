defmodule HoneydewTest do
  use ExUnit.Case, async: false

  import Helper
  import Honeydew.CrashLoggerHelpers

  alias Honeydew.Job
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.Workers

  @moduletag :capture_log

  setup [:restart_honeydew, :setup_echoing_error_logger]

  defmodule EchoingFailureMode do
    alias Honeydew.Job
    alias Honeydew.Queue
    @behaviour Honeydew.FailureMode

    def validate_args!([test_pid]) when is_pid(test_pid), do: :ok

    def handle_failure(%Job{queue: queue, from: from} = job, reason, [test_pid]) do
      send test_pid, {:job_failed, reason}

      # tell the queue that that job can be removed.
      queue
      |> Honeydew.get_queue
      |> Queue.ack(job)

      # send the error to the awaiting process, if necessary
      with {owner, _ref} <- from,
        do: send(owner, %{job | result: {:error, reason}})
    end

    def await_job_failure_reason do
      assert_receive({:job_failed, reason})
      reason
    end
  end

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

    assert_receive %Job{private: ^id, result: {:ok, :noop}}
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
      fn -> Process.exit(self(), :kill) end |> Honeydew.async(queue)
      fn -> spawn_link(fn -> :ok end); Process.sleep(200) end |> Honeydew.async(queue)
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

  test "job runners don't die when a linked process terminates normally" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue)
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn -> spawn_link(fn -> :ok end); Process.sleep(100) end |> Honeydew.async(queue)
    Process.sleep(200)

    assert [worker] == workers(queue)
  end

  test "when a job crashes with an exception" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    job = fn -> raise "intentional crash" end |> Honeydew.async(queue)

    assert {%RuntimeError{message: "intentional crash"}, stacktrace} =
      EchoingFailureMode.await_job_failure_reason()
    assert is_list(stacktrace)
    assert_crash_logged(job)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
  end

  test "when a job crashes with an uncaught throw" do
    queue = :erlang.unique_integer
    thrown = :ice_cream_cone

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    job = fn -> throw(thrown) end |> Honeydew.async(queue)

    assert {^thrown, stacktrace} =
      EchoingFailureMode.await_job_failure_reason()
    assert is_list(stacktrace)
    assert_crash_logged(job)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
  end

  test "when a job calls :erlang.raise(:exit, reason, stacktrace) directly" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    job = fn ->
      :erlang.raise(:exit, :eject, [])
      Process.sleep(:infinity)
    end |> Honeydew.async(queue)

    assert :eject = EchoingFailureMode.await_job_failure_reason()
    assert_crash_logged(job)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
  end

  test "when a job's Task times out" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    me = self()

    job = fn ->
      task =
        Task.async(fn ->
          Process.sleep(:infinity)
        end)

      send(me, {:task, task})

      Task.await(task, 1)
    end |> Honeydew.async(queue)

    task =
      receive do
        {:task, task} -> task
      end

    assert {:timeout, {Task, :await, [^task, 1]}} = EchoingFailureMode.await_job_failure_reason()
    assert_crash_logged(job)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
  end

  test "when a worker is terminated externally" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    job =
      fn ->
        Process.sleep(:infinity)
      end
      |> Honeydew.async(queue)

    # Without Process.sleep, the failure reason becomes :noproc because the
    # worker is killed before the job monitor can monitor it
    Process.sleep(100)

    Process.exit(worker, :kill)

    assert :killed = EchoingFailureMode.await_job_failure_reason()
    assert_crash_logged(job)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
  end

  test "when a linked process terminates abnormally" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn ->
      spawn_link(fn -> raise "intentional crash" end)
      Process.sleep(200)
    end
    |> Honeydew.async(queue)

    # # TODO: enable this when https://github.com/koudelka/honeydew/pull/56 is
    # # fixed
    # assert {%RuntimeError{message: "intentional crash"}, stacktrace} =
    #   EchoingFailureMode.await_job_failure_reason()
    # assert is_list(stacktrace)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
  end

  test "when a job exits" do
    queue = :erlang.unique_integer

    :ok = Honeydew.start_queue(queue, failure_mode: {EchoingFailureMode, [self()]})
    :ok = Honeydew.start_workers(queue, Stateless, num: 1)

    [worker] = workers(queue)

    fn ->
      Process.exit(self(), :eject)
    end |> Honeydew.async(queue)

    Process.sleep(100)

    assert_worker_restarted(queue, worker)
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
      {:init, worker} -> send worker, :exit
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

  defp assert_worker_restarted(queue, worker) do
    [new_worker] = workers(queue)

    assert worker != new_worker
  end

  defp assert_crash_logged(%Job{private: private}) do
    assert_receive {:honeydew_crash_log, {level, pid, {_mod, _msg, _ts, metadata}}}

    assert Keyword.has_key?(metadata, :honeydew_crash_reason)
    assert ^private = Keyword.fetch!(metadata, :honeydew_job) |> Map.fetch!(:private)
  end
end
