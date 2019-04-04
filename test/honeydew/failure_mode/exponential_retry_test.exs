defmodule Honeydew.FailureMode.ExponentialRetryTest do
  use ExUnit.Case, async: true

  alias Honeydew.Queue.Mnesia

  @moduletag :capture_log

  setup do
    queue = :erlang.unique_integer
    failure_queue = "#{queue}_failed"

    :ok = Honeydew.start_queue(queue, queue: {Mnesia, ram_copies: [node()]},
                                      failure_mode: {Honeydew.FailureMode.ExponentialRetry,
                                                     times: 3,
                                                     finally: {Honeydew.FailureMode.Move, queue: failure_queue}})
    :ok = Honeydew.start_queue(failure_queue, queue: {Mnesia, [ram_copies: [node()]]})
    :ok = Honeydew.start_workers(queue, Stateless)

    [queue: queue, failure_queue: failure_queue]
  end

  test "validate_args!/1" do
    import Honeydew.FailureMode.ExponentialRetry, only: [validate_args!: 1]

    assert :ok = validate_args!([times: 2])
    assert :ok = validate_args!([times: 2, finally: {Honeydew.FailureMode.Move, [queue: :abc]}])

    assert_raise ArgumentError, fn ->
      validate_args!([base: -1])
    end

    assert_raise ArgumentError, fn ->
      validate_args!(:abc)
    end

    assert_raise ArgumentError, fn ->
      validate_args!([fun: fn _job, _reason -> :halt end])
    end

    assert_raise ArgumentError, fn ->
      validate_args!([times: -1])
    end

    assert_raise ArgumentError, fn ->
      validate_args!([times: 2, finally: {Honeydew.FailureMode.Move, [bad: :args]}])
    end

    assert_raise ArgumentError, fn ->
      validate_args!([times: 2, finally: {"bad", []}])
    end
  end

  test "should retry the job with exponentially increasing delays", %{queue: queue, failure_queue: failure_queue} do
    {:crash, [self()]} |> Honeydew.async(queue)

    delays =
      Enum.map(0..3, fn _ ->
        receive do
          :job_ran ->
            DateTime.utc_now()
        end
      end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> DateTime.diff(b, a) end)

    # 2^0 - 1 -> 0 sec delay
    # 2^1 - 1 -> 1 sec delay
    # 2^2 - 1 -> 3 sec delay
    assert_in_delta Enum.at(delays, 0), 0, 1
    assert_in_delta Enum.at(delays, 1), 1, 1
    assert_in_delta Enum.at(delays, 2), 3, 1

    assert Honeydew.status(queue) |> get_in([:queue, :count]) == 0
    refute_receive :job_ran

    assert Honeydew.status(failure_queue) |> get_in([:queue, :count]) == 1
  end
end
