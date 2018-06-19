defmodule HoneydewTest do
  use ExUnit.Case, async: true
  alias Honeydew.Job
  alias Honeydew.FailureMode.Abandon
  alias Honeydew.SuccessMode.Log

  test "queue_spec/2" do
    queue = :erlang.unique_integer

    spec =
      Honeydew.queue_spec(
        queue,
        queue: {:abc, [1,2,3]},
        dispatcher: {Dis.Patcher, [:a, :b]},
        failure_mode: {Abandon, []},
        success_mode: {Log, []},
        supervisor_opts: [id: :my_queue_supervisor],
        suspended: true)

    assert spec == %{
      id: :my_queue_supervisor,
      start: {Honeydew.QueueSupervisor, :start_link,
              [queue, :abc, [1, 2, 3], 1, {Dis.Patcher, [:a, :b]},
               {Abandon, []}, {Log, []}, true]},
      restart: :permanent,
      shutdown: :infinity
    }
  end

  test "queue_spec/2 should raise when failure/success mode args are invalid" do
    queue = :erlang.unique_integer

    assert_raise ArgumentError, fn ->
      Honeydew.queue_spec(queue, failure_mode: {Abandon, [:abc]})
    end

    assert_raise ArgumentError, fn ->
      Honeydew.queue_spec(queue, success_mode: {Log, [:abc]})
    end
  end

  test "queue_spec/2 defaults" do
    queue = :erlang.unique_integer
    spec =  Honeydew.queue_spec(queue)

    assert spec == %{
      id: {:queue, queue},
      start: {Honeydew.QueueSupervisor, :start_link,
              [queue, Honeydew.Queue.ErlangQueue, [], 1,
               {Honeydew.Dispatcher.LRU, []}, {Honeydew.FailureMode.Abandon, []}, nil, false]},
      restart: :permanent,
      shutdown: :infinity
    }

    queue = {:global, :erlang.unique_integer}
    spec =  Honeydew.queue_spec(queue)

    assert spec == %{
      id: {:queue, queue},
      start: {Honeydew.QueueSupervisor, :start_link,
              [queue, Honeydew.Queue.ErlangQueue, [], 1,
               {Honeydew.Dispatcher.LRUNode, []}, {Honeydew.FailureMode.Abandon, []}, nil, false]},
      restart: :permanent,
      shutdown: :infinity
    }
  end

  test "worker_spec/2" do
    queue = :erlang.unique_integer

    spec = Honeydew.worker_spec(
      queue,
      {Worker, [1, 2, 3]},
      num: 123,
      init_retry_secs: 5,
      supervisor_opts: [id: :my_worker_supervisor])

    assert spec == {:my_worker_supervisor,
                    {Honeydew.Workers, :start_link,
                     [queue, %{init_retry: 5, ma: {Worker, [1,2,3]}, nodes: [], num: 123, shutdown: 10000}]}, :permanent,
                    :infinity, :supervisor, [Honeydew.Workers]}
  end

  test "worker_spec/2 defaults" do
    queue = :erlang.unique_integer

    spec =  Honeydew.worker_spec(queue, Worker)
    assert spec == {{:worker, queue},
                    {Honeydew.Workers, :start_link,
                    [queue, %{init_retry: 5, ma: {Worker, []}, nodes: [], num: 10, shutdown: 10000}]}, :permanent,
                    :infinity, :supervisor, [Honeydew.Workers]}
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
