defmodule Honeydew.FailureMode.RetryTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  setup do
    queue = :erlang.unique_integer
    failure_queue = "#{queue}_failed"

    :ok = Honeydew.start_queue(queue, failure_mode: {Honeydew.FailureMode.Retry,
                                                     times: 3, finally: {Honeydew.FailureMode.Move, queue: failure_queue}})
    :ok = Honeydew.start_queue(failure_queue)
    :ok = Honeydew.start_workers(queue, Stateless)

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

  test "should retry the job", %{queue: queue, failure_queue: failure_queue} do
    {:crash, [self()]} |> Honeydew.async(queue)
    assert_receive :job_ran
    assert_receive :job_ran
    assert_receive :job_ran
    assert_receive :job_ran

    Process.sleep(500) # let the Move failure mode do its thing

    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 0
    refute_receive :job_ran

    assert Honeydew.status(failure_queue) |> get_in([:queue, :count]) == 1
  end

  test "should inform the awaiting process of the exception", %{queue: queue, failure_queue: failure_queue} do
    job = {:crash, [self()]} |> Honeydew.async(queue, reply: true)

    assert {:retrying, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:moved, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)

    :ok = Honeydew.start_workers(failure_queue, Stateless)

    # job ran in the failure queue
    assert {:error, {%RuntimeError{message: "ignore this crash"}, _stacktrace}} = Honeydew.yield(job)
  end

  test "should inform the awaiting process of an uncaught throw", %{queue: queue, failure_queue: failure_queue} do
    job = fn -> throw "intentional crash" end |> Honeydew.async(queue, reply: true)

    assert {:retrying, {"intentional crash", _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {"intentional crash", _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {"intentional crash", _stacktrace}} = Honeydew.yield(job)
    assert {:moved, {"intentional crash", _stacktrace}} = Honeydew.yield(job)

    :ok = Honeydew.start_workers(failure_queue, Stateless)

    # job ran in the failure queue
    assert {:error, {"intentional crash", _stacktrace}} = Honeydew.yield(job)
  end

  test "should inform the awaiting process when the linked process terminates abnormally", %{queue: queue, failure_queue: failure_queue} do
    job =
      fn ->
        spawn_link(fn -> throw "intentional crash" end)
        Process.sleep(100)
      end
      |> Honeydew.async(queue, reply: true)

    assert {:retrying, {%RuntimeError{message: "intentional crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {%RuntimeError{message: "intentional crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:retrying, {%RuntimeError{message: "intentional crash"}, _stacktrace}} = Honeydew.yield(job)
    assert {:moved, {%RuntimeError{message: "intentional crash"}, _stacktrace}} = Honeydew.yield(job)

    :ok = Honeydew.start_workers(failure_queue, Stateless)

    # # job ran in the failure queue
    assert {:error, {%RuntimeError{message: "intentional crash"}, _stacktrace}} = Honeydew.yield(job)
  end
end
