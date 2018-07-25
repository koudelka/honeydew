defmodule Honeydew.QueuesTest do
  use ExUnit.Case, async: true
  import Helper
  alias Honeydew.Queues
  alias Honeydew.Queue.State
  alias Honeydew.Queue.ErlangQueue
  alias Honeydew.Queue.Mnesia
  alias Honeydew.Dispatcher.LRU
  alias Honeydew.Dispatcher.MRU
  alias Honeydew.FailureMode.Abandon
  alias Honeydew.FailureMode.Retry
  alias Honeydew.SuccessMode.Log

  setup :restart_honeydew

  test "stop_queue/2 removes child spec" do
    :ok = Honeydew.start_queue(:abc)
    assert [{:abc, _, _, _}] = Supervisor.which_children(Queues)

    :ok = Honeydew.stop_queue(:abc)
    assert Enum.empty? Supervisor.which_children(Queues)
  end

  describe "start_queue/2" do
    test "options" do
      nodes = [node()]

      options = [
        queue: {Mnesia, [nodes, [disc_copies: nodes], []]},
        dispatcher: {MRU, []},
        failure_mode: {Retry, [times: 5]},
        success_mode: {Log, []},
        suspended: true
      ]

      :ok = Honeydew.start_queue({:global, :abc}, options)
      assert [{{:global, :abc}, pid, _, _}] = Supervisor.which_children(Queues)

      assert %State{
        dispatcher: {Honeydew.Dispatcher.MRU, _dispatcher_state},
        failure_mode: {Honeydew.FailureMode.Retry, [times: 5]},
        module: Honeydew.Queue.Mnesia,
        queue: {:global, :abc},
        success_mode: {Honeydew.SuccessMode.Log, []},
        suspended: true
      } = :sys.get_state(pid)
    end

    test "raises when failure/success mode args are invalid" do
      assert_raise ArgumentError, fn ->
        Honeydew.start_queue(:abc, failure_mode: {Abandon, [:abc]})
      end

      assert_raise ArgumentError, fn ->
        Honeydew.start_queue(:abc, success_mode: {Log, [:abc]})
      end
    end

    test "default options" do
      :ok = Honeydew.start_queue(:abc)
      assert [{:abc, pid, _, _}] = Supervisor.which_children(Queues)

      assert %State{
        dispatcher: {LRU, _dispatcher_state},
        failure_mode: {Abandon, []},
        module: ErlangQueue,
        queue: :abc,
        success_mode: nil,
        suspended: false
      } = :sys.get_state(pid)
    end
  end
end
