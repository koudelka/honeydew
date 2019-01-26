defmodule Honeydew.Progress do
  @moduledoc false

  alias Honeydew.JobMonitor

  def progress(update) do
    :ok =
      :job_monitor
      |> Process.get
      |> JobMonitor.progress(update)
  end

end
