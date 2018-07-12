defmodule Honeydew.Progress do
  def progress(update) do
    monitor = Process.get(:job_monitor)
    :ok = GenServer.call(monitor, {:progress, update})
  end
end
