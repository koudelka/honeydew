defmodule HoneydewTest do
  use ExUnit.Case, async: false
  import Helper
  alias Honeydew.Job
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.Workers

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

end
