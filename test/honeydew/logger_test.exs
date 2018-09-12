defmodule Honeydew.LoggerTest do
  use ExUnit.Case, async: false

  import Honeydew.CrashLoggerHelpers

  alias Honeydew.Crash
  alias Honeydew.Job
  alias Honeydew.Logger, as: HoneydewLogger
  alias Honeydew.Logger.Metadata

  setup [:setup_echoing_error_logger]

  @moduletag :capture_log

  test "worker_init_crashed/1 with an exception crash" do
    module = __MODULE__
    error = RuntimeError.exception("foo")
    stacktrace = []
    crash = Crash.new(:exception, error, stacktrace)

    :ok = HoneydewLogger.worker_init_crashed(module, crash)

    assert_receive {:honeydew_crash_log, event}
    assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
    assert msg =~ ~r/#{inspect(module)}.init\/1 must return \{:ok, .* but raised #{inspect(error)}/
    assert Keyword.fetch!(metadata, :honeydew_crash_reason) == Metadata.build_crash_reason(crash)
  end

  test "worker_init_crashed/1 with an uncaught throw crash" do
    module = __MODULE__
    thrown = :grenade
    stacktrace = []
    crash = Crash.new(:throw, thrown, stacktrace)

    :ok = HoneydewLogger.worker_init_crashed(module, crash)

    assert_receive {:honeydew_crash_log, event}
    assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
    assert msg =~ ~r/#{inspect(module)}.init\/1 must return \{:ok, .* but threw #{inspect(thrown)}/
    assert Keyword.fetch!(metadata, :honeydew_crash_reason) == Metadata.build_crash_reason(crash)
  end

  test "worker_init_crashed/1 with a bad return value crash" do
    module = __MODULE__
    value = "1 million dollars"
    crash = Crash.new(:bad_return_value, value)

    :ok = HoneydewLogger.worker_init_crashed(module, crash)

    assert_receive {:honeydew_crash_log, event}
    assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
    assert msg =~ ~r/#{inspect(module)}.init\/1 must return \{:ok, .*, got: #{inspect(value)}/
    assert Keyword.fetch!(metadata, :honeydew_crash_reason) == Metadata.build_crash_reason(crash)
  end

  test "job_failed/1 with an exception crash" do
    job = %Job{}
    error = RuntimeError.exception("foo")
    stacktrace = []
    crash = Crash.new(:exception, error, stacktrace)

    :ok = HoneydewLogger.job_failed(job, crash)

    assert_receive {:honeydew_crash_log, event}
    assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
    assert msg =~ ~r/job failed due to exception/i
    assert Keyword.fetch!(metadata, :honeydew_crash_reason) == Metadata.build_crash_reason(crash)
  end

  test "job_failed/1 with an uncaught throw crash" do
    job = %Job{}
    thrown = :grenade
    stacktrace = []
    crash = Crash.new(:throw, thrown, stacktrace)

    :ok = HoneydewLogger.job_failed(job, crash)

    assert_receive {:honeydew_crash_log, event}
    assert {:warn, _, {Logger, msg, _timestamp, metadata}} = event
    assert msg =~ ~r/job failed due to uncaught throw/i
    assert Keyword.fetch!(metadata, :honeydew_crash_reason) == Metadata.build_crash_reason(crash)
  end
end
