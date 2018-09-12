defmodule Honeydew.Logger do
  @moduledoc false

  alias Honeydew.Crash
  alias Honeydew.Logger.Metadata
  alias Honeydew.Job

  require Logger

  def worker_init_crashed(module, %Crash{type: :exception, reason: exception} = crash) do
    Logger.warn(fn ->
      {
        "#{module}.init/1 must return {:ok, state :: any()}, but raised #{inspect(exception)}",
        honeydew_crash_reason: Metadata.build_crash_reason(crash)
      }
    end)
  end

  def worker_init_crashed(module, %Crash{type: :throw, reason: thrown} = crash) do
    Logger.warn(fn ->
      {
        "#{module}.init/1 must return {:ok, state :: any()}, but threw #{inspect(thrown)}",
        honeydew_crash_reason: Metadata.build_crash_reason(crash)
      }
    end)
  end

  def worker_init_crashed(module, %Crash{type: :bad_return_value, reason: value} = crash) do
    Logger.warn(fn ->
      {
        "#{module}.init/1 must return {:ok, state :: any()}, got: #{inspect value}",
        honeydew_crash_reason: Metadata.build_crash_reason(crash)
      }
    end)
  end

  def job_failed(%Job{} = job, %Crash{type: :exception} = crash) do
    Logger.warn(fn ->
      {
        """
        Job failed due to exception. #{inspect(job)}
        #{format_crash_for_log(crash)}
        """,
        honeydew_crash_reason: Metadata.build_crash_reason(crash)
      }
    end)
  end

  def job_failed(%Job{} = job, %Crash{type: :throw} = crash) do
    Logger.warn(fn ->
      {
        """
        Job failed due to uncaught throw. #{inspect job}",
        #{format_crash_for_log(crash)}
        """,
        honeydew_crash_reason: Metadata.build_crash_reason(crash)
      }
    end)
  end

  defp format_crash_for_log(%Crash{type: :exception, reason: exception, stacktrace: stacktrace}) do
    Exception.format(:error, exception, stacktrace)
  end

  defp format_crash_for_log(%Crash{type: :throw, reason: exception, stacktrace: stacktrace}) do
    Exception.format(:throw, exception, stacktrace)
  end
end
