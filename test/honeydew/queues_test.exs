defmodule Honeydew.QueuesTest do
  use ExUnit.Case, async: true
  alias Honeydew.Queue.ErlangQueue
  alias Honeydew.FailureMode.Abandon
  alias Honeydew.SuccessMode.Log

  setup do
    pool = :erlang.unique_integer

    Honeydew.create_groups(pool)

    {:ok, supervisor} = Honeydew.Queues.start_link([3, pool, ErlangQueue, [], {Honeydew.Dispatcher.LRU, []}, {Abandon, []}, nil, false])

    # on_exit fn ->
    #   Supervisor.stop(supervisor)
    #   Honeydew.delete_groups(pool)
    # end

    [supervisor: supervisor]
  end

  test "starts the correct number of queues", context do
    assert context[:supervisor]
    |> Supervisor.which_children
    |> Enum.count == 3
  end

  test "starts the given queue module", context do
    assert   {_, _, _, [Honeydew.Queue]} = context[:supervisor] |> Supervisor.which_children |> List.first
  end

  test "child_spec/2" do
    queue = :erlang.unique_integer

    spec =
      Honeydew.Queues.child_spec([
        queue,
        queue: {:abc, [1,2,3]},
        dispatcher: {Dis.Patcher, [:a, :b]},
        failure_mode: {Abandon, []},
        success_mode: {Log, []},
        supervisor_opts: [id: :my_queue_supervisor],
        suspended: true])

    assert spec == %{
      id: :my_queue_supervisor,
      type: :supervisor,
      start: {Honeydew.Queues, :start_link,
              [[1, queue, :abc, [1, 2, 3], {Dis.Patcher, [:a, :b]},
               {Abandon, []}, {Log, []}, true]]}
    }
  end

  test "child_spec/2 should raise when failure/success mode args are invalid" do
    queue = :erlang.unique_integer

    assert_raise ArgumentError, fn ->
      Honeydew.Queues.child_spec([queue, failure_mode: {Abandon, [:abc]}])
    end

    assert_raise ArgumentError, fn ->
      Honeydew.Queues.child_spec([queue, success_mode: {Log, [:abc]}])
    end
  end

  test "child_spec/2 defaults" do
    queue = :erlang.unique_integer
    spec =  Honeydew.Queues.child_spec([queue])

    assert spec == %{
      id: {:queue, queue},
      type: :supervisor,
      start: {Honeydew.Queues, :start_link,
              [[1, queue, Honeydew.Queue.ErlangQueue, [],
               {Honeydew.Dispatcher.LRU, []}, {Abandon, []}, nil, false]]}
    }

    queue = {:global, :erlang.unique_integer}
    spec =  Honeydew.Queues.child_spec([queue])

    assert spec == %{
      id: {:queue, queue},
      type: :supervisor,
      start: {Honeydew.Queues, :start_link,
              [[1, queue, Honeydew.Queue.ErlangQueue, [],
               {Honeydew.Dispatcher.LRUNode, []}, {Abandon, []}, nil, false]]}
    }
  end

end
