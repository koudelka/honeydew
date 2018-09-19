defmodule Honeydew.WorkerTest do
  use ExUnit.Case

  import Honeydew.CrashLoggerHelpers

  defmodule WorkerWithBadInit do
    @behaviour Honeydew.Worker
    def init(:raise), do: raise "Boom"
    def init(:throw), do: throw :boom
    def init(:bad), do: :bad
    def init(:ok), do: {:ok, %{}}
  end

  setup [:setup_queue_name, :setup_queue, :setup_worker_pool]

  @moduletag :capture_log

  @tag :start_workers
  test "workers should die when their queue dies", %{queue: queue} do
    queue_pid = Honeydew.get_queue(queue)
    %{workers: workers} = Honeydew.status(queue)

    Process.exit(queue_pid, :kill)

    Process.sleep(100)

    workers
    |> Map.keys
    |> Enum.each(fn w -> assert not Process.alive?(w) end)
  end

  describe "logging and exception handling" do
    setup [:setup_echoing_error_logger]

    test "when init/1 callback raises an exception", %{queue: queue} do
      expected_error = %RuntimeError{message: "Boom"}
      Honeydew.start_workers(queue, {WorkerWithBadInit, :raise}, num: 1)

      assert_receive {:honeydew_crash_log, event}
      assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
      assert msg =~ ~r/#{inspect(WorkerWithBadInit)}.init\/1 must return \{:ok, .* but raised #{inspect(expected_error)}/
      assert {^expected_error, stacktrace} = Keyword.fetch!(metadata, :honeydew_crash_reason)
      assert is_list(stacktrace)
    end

    test "when init/1 callback throws an atom", %{queue: queue} do
      Honeydew.start_workers(queue, {WorkerWithBadInit, :throw}, num: 1)

      assert_receive {:honeydew_crash_log, event}
      assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
      assert msg =~ ~r/#{inspect(WorkerWithBadInit)}.init\/1 must return \{:ok, .* but threw #{inspect(:boom)}/
      assert {{:nocatch, :boom}, stacktrace} = Keyword.fetch!(metadata, :honeydew_crash_reason)
      assert is_list(stacktrace)
    end

    test "when init/1 callback returns a bad return value", %{queue: queue} do
      Honeydew.start_workers(queue, {WorkerWithBadInit, :bad}, num: 1)

      assert_receive {:honeydew_crash_log, event}
      assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
      assert msg =~ ~r/#{inspect(WorkerWithBadInit)}.init\/1 must return \{:ok, .*, got: #{inspect(:bad)}/
      assert {{:bad_return_value, :bad}, []} = Keyword.fetch!(metadata, :honeydew_crash_reason)
    end

    test "when init/1 callback returns {:ok, state}", %{queue: queue} do
      Honeydew.start_workers(queue, {WorkerWithBadInit, :ok}, num: 1)

      refute_receive {:honeydew_crash_log, _event}
    end
  end

  defp setup_queue_name(%{queue: queue}), do: {:ok, [queue: queue]}
  defp setup_queue_name(_), do: {:ok, [queue: generate_queue_name()]}

  defp setup_queue(%{queue: queue}) do
    :ok = Honeydew.start_queue(queue)

    on_exit fn ->
      Honeydew.stop_queue(queue)
    end
  end

  defp setup_worker_pool(%{queue: queue, start_workers: true}) do
    :ok = Honeydew.start_workers(queue, Stateless, num: 10)

    on_exit fn ->
      Honeydew.stop_workers(queue)
    end
  end

  defp setup_worker_pool(_), do: :ok

  defp generate_queue_name do
    :erlang.unique_integer |> to_string
  end
end
