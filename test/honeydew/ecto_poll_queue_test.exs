defmodule Honeydew.EctoPollQueueTest do
  use ExUnit.Case, async: true
  alias Honeydew.EctoPollQueue
  alias Honeydew.FailureMode.Abandon

  describe "child_spec/1" do
    test "provides a supervision spec" do
      queue = :erlang.unique_integer

      spec = EctoPollQueue.child_spec([queue,
                                       schema: :my_schema,
                                       repo: :my_repo,
                                       poll_interval: 123,
                                       stale_timeout: 456,
                                       failure_mode: {Abandon, []}])

      assert spec == {{:queue, queue},
                      {Honeydew.QueueSupervisor, :start_link,
                      [queue,
                        Honeydew.PollQueue, [Honeydew.EctoSource, [schema: :my_schema,
                                                                  repo: :my_repo,
                                                                  poll_interval: 123,
                                                                  stale_timeout: 456]],
                        1,
                        {Honeydew.Dispatcher.LRU, []},
                        {Abandon, []},
                        nil, false]}, :permanent, :infinity, :supervisor, [Honeydew.QueueSupervisor]}
    end

    test "defaults" do
      queue = :erlang.unique_integer
      spec = EctoPollQueue.child_spec([queue, schema: :my_schema, repo: :my_repo])

      assert spec == {{:queue, queue},
                      {Honeydew.QueueSupervisor, :start_link,
                       [queue,
                        Honeydew.PollQueue, [Honeydew.EctoSource, [schema: :my_schema,
                                                                   repo: :my_repo,
                                                                   poll_interval: 10,
                                                                   stale_timeout: 300]],
                        1,
                        {Honeydew.Dispatcher.LRU, []},
                        {Abandon, []},
                        nil, false]}, :permanent, :infinity, :supervisor, [Honeydew.QueueSupervisor]}
    end


    test "should raise when :queue argument provided" do
      queue = :erlang.unique_integer

      assert_raise ArgumentError, fn ->
        EctoPollQueue.child_spec([queue, schema: :abc, repo: :abc, queue: :abc])
      end
    end

    test "should raise when :repo or :schema arguments aren't provided" do
      queue = :erlang.unique_integer

      assert_raise KeyError, fn ->
        EctoPollQueue.child_spec([queue, repo: :abc])
      end

      assert_raise KeyError, fn ->
        EctoPollQueue.child_spec([queue, schema: :abc])
      end
    end
  end

end
