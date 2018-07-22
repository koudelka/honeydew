defmodule HoneydewTest do
  use ExUnit.Case, async: false
  alias Honeydew.Job
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.Workers

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
