defmodule HoneydewTest do
  use ExUnit.Case, async: true
  alias Honeydew.Job

  test "worker_spec/2" do
    queue = :erlang.unique_integer

    spec = Honeydew.worker_spec(
      queue,
      {Worker, [1, 2, 3]},
      num: 123,
      init_retry_secs: 5,
      supervisor_opts: [id: :my_worker_supervisor])

    assert spec == %{
      id: :my_worker_supervisor,
      type: :supervisor,
      start: {Honeydew.Workers, :start_link,
              [queue, %{init_retry: 5, ma: {Worker, [1,2,3]}, nodes: [], num: 123, shutdown: 10000}]}
    }
  end

  test "worker_spec/2 defaults" do
    queue = :erlang.unique_integer

    spec =  Honeydew.worker_spec(queue, Worker)

    assert spec == %{
      id: {:worker, queue},
      type: :supervisor,
      start: {Honeydew.Workers, :start_link,
              [queue, %{init_retry: 5, ma: {Worker, []}, nodes: [], num: 10, shutdown: 10000}]}
    }
  end

  test "group/1" do
    assert Honeydew.group(:my_queue, :workers) == :"honeydew.workers.my_queue"
  end

  test "supervisor/1" do
    assert Honeydew.supervisor(:my_queue, :worker) == :"honeydew.worker_supervisor.my_queue"
  end

  test "supervisor/1 with global queue" do
    assert Honeydew.supervisor({:global, :my_queue}, :worker) == :"honeydew.worker_supervisor.global.my_queue"
  end

  test "table_name/1" do
    assert Honeydew.table_name({:global, :my_queue}) == "global_my_queue"
    assert Honeydew.table_name(:my_queue) == "my_queue"
  end

  test "success mode smoke test" do
    queue = :erlang.unique_integer
    {:ok, _} = Helper.start_queue_link(queue, success_mode: {TestSuccessMode, [to: self()]})
    {:ok, _} = Helper.start_worker_link(queue, Stateless)

    %Job{private: id} = fn -> :noop end |> Honeydew.async(queue)

    assert_receive %Job{private: ^id}
  end

  test "progress updates" do
    queue = :erlang.unique_integer
    {:ok, _} = Helper.start_queue_link(queue)
    {:ok, _} = Helper.start_worker_link(queue, Stateless)

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
