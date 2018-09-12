defmodule Honeydew.Logger.MetadataTest do
  use ExUnit.Case, async: true

  alias Honeydew.Crash
  alias Honeydew.Logger.Metadata

  test "build_crash_reason/1 with an exception crash" do
    exception = RuntimeError.exception("foo")
    stacktrace = []
    crash = Crash.new(:exception, exception, stacktrace)

    assert {^exception, ^stacktrace} = Metadata.build_crash_reason(crash)
  end

  test "build_crash_reason/1 with an uncaught throw crash" do
    thrown = :baseball
    stacktrace = []
    crash = Crash.new(:throw, thrown, stacktrace)

    assert {{:nocatch, ^thrown}, ^stacktrace} = Metadata.build_crash_reason(crash)
  end

  test "build_crash_reason/1 with a bad return value" do
    value = :boom
    crash = Crash.new(:bad_return_value, value)

    assert {{:bad_return_value, ^value}, []} = Metadata.build_crash_reason(crash)
  end
end
