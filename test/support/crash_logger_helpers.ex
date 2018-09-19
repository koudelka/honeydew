defmodule Honeydew.CrashLoggerHelpers do
  @moduledoc """
  Helpers for testing honeydew crash logs
  """

  import ExUnit.Callbacks

  defmodule EchoingHoneydewCrashLoggerBackend do
    @moduledoc false
    @behaviour :gen_event

    def init(_) do
      {:ok, %{}}
    end

    def handle_call({:configure, opts}, state) do
      target = Keyword.fetch!(opts, :target)
      {:ok, :ok, Map.put(state, :target, target)}
    end

    def handle_event({_level, _from, {Logger, _msg, _ts, metadata}} =event, %{target: target} = state) when is_pid(target) do
      if Keyword.has_key?(metadata, :honeydew_crash_reason) do
        send(target, {:honeydew_crash_log, event})
      end
      {:ok, state}
    end

    def handle_event(_, state), do: {:ok, state}

    def handle_info(_msg, state) do
      {:ok, state}
    end
  end

  @doc """
  Sets up an error logger backend that sends `{:honeydew_crash_log, event}`
  messages on any log statement that has `:honeydew_crash_reason` in its
  metadata.
  """
  def setup_echoing_error_logger(_) do
    test_pid = self()
    Logger.add_backend(EchoingHoneydewCrashLoggerBackend, target: test_pid)
    Logger.configure_backend(EchoingHoneydewCrashLoggerBackend, target: test_pid)

    on_exit fn ->
      Logger.remove_backend(EchoingLoggerBackend)
      wait_backend_removal(EchoingLoggerBackend)
    end
  end

  defp wait_backend_removal(module) do
    if module in :gen_event.which_handlers(Logger) do
      Process.sleep(20)
      wait_backend_removal(module)
    else
      :ok
    end
  end
end
