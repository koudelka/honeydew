defmodule Honeydew.FailureMode.AbandonTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  setup do
    queue = :erlang.unique_integer
    :ok = Honeydew.start_queue(queue, failure_mode: Honeydew.FailureMode.Abandon)
    :ok = Honeydew.start_workers(queue, Stateless)

    [queue: queue]
  end

  test "validate_args!/1" do
    import Honeydew.FailureMode.Abandon, only: [validate_args!: 1]

    assert :ok = validate_args!([])

    assert_raise ArgumentError, fn ->
      validate_args!(:abc)
    end
  end

  test "should remove job from the queue", %{queue: queue} do
    {:crash, [self()]} |> Honeydew.async(queue)
    assert_receive :job_ran

    Process.sleep(100) # let the failure mode do its thing

    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 0
    refute_receive :job_ran
  end

  test "should inform the awaiting process of the exception", %{queue: queue} do
    {:error, reason} =
      {:crash, [self()]}
      |> Honeydew.async(queue, reply: true)
      |> Honeydew.yield

    assert {%RuntimeError{message: "ignore this crash"}, stacktrace} = reason
    assert is_list(stacktrace)
  end

  test "should inform the awaiting process of an uncaught throw", %{queue: queue} do
    {:error, reason} =
      fn -> throw "intentional crash" end
      |> Honeydew.async(queue, reply: true)
      |> Honeydew.yield

    assert {"intentional crash", stacktrace} = reason
    assert is_list(stacktrace)
  end

  test "should inform the awaiting process when the linked process terminates abnormally", %{queue: queue} do
    {:error, reason} =
      fn ->
        spawn_link(fn -> raise "intentional crash" end)
        Process.sleep(100)
      end
      |> Honeydew.async(queue, reply: true)
      |> Honeydew.yield

    assert {%RuntimeError{message: "intentional crash"}, stacktrace} = reason
    assert is_list(stacktrace)
  end
end
