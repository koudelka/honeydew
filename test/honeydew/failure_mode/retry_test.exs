defmodule Honeydew.FailureMode.RetryTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  setup context do
    queue = :erlang.unique_integer
    failure_queue = "#{queue}_failed"
    retry_count = Map.get(context, :retry_count, 3)

    {:ok, _} = Helper.start_queue_link(queue, failure_mode: {Honeydew.FailureMode.Retry,
                                                             times: retry_count, finally: {Honeydew.FailureMode.Move, queue: failure_queue}})
    {:ok, _} = Helper.start_queue_link(failure_queue)
    {:ok, _} = Helper.start_worker_link(queue, Stateless)

    [queue: queue, failure_queue: failure_queue]
  end

  test "validate_args!/1" do
    import Honeydew.FailureMode.Retry, only: [validate_args!: 1]

    assert :ok = validate_args!([times: 2])
    assert :ok = validate_args!([times: 2, finally: {Honeydew.FailureMode.Move, [queue: :abc]}])

    assert_raise ArgumentError, fn ->
      validate_args!(:abc)
    end

    assert_raise ArgumentError, fn ->
      validate_args!([times: -1])
    end

    assert_raise ArgumentError, fn ->
      validate_args!([times: 2, finally: {Honeydew.FailureMode.Move, [bad: :args]}])
    end
  end

  @tag retry_count: 3
  test "should retry the job", %{queue: queue, failure_queue: failure_queue} do
    {:crash, [self()]} |> Honeydew.async(queue)
    assert_receive :job_ran
    assert_receive :job_ran
    assert_receive :job_ran

    Process.sleep(500) # let the Move failure mode do its thing

    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 0
    refute_receive :job_ran

    assert Honeydew.status(failure_queue) |> get_in([:queue, :count]) == 1
  end

  @tag retry_count: 1
  test "when retry_count is 1", %{queue: queue, failure_queue: failure_queue} do
    {:crash, [self()]} |> Honeydew.async(queue)
    assert_receive :job_ran

    Process.sleep(500) # let the Move failure mode do its thing

    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 0
    refute_receive :job_ran

    assert Honeydew.status(failure_queue) |> get_in([:queue, :count]) == 1
  end

  test "should inform the awaiting process of the error", %{queue: queue, failure_queue: failure_queue} do
    job = {:crash, [self()]} |> Honeydew.async(queue, reply: true)

    assert {:retrying, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:moved, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)

    {:ok, _} = Helper.start_worker_link(failure_queue, Stateless)

    # # job ran in the failure queue
    assert {:error, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
  end
end
