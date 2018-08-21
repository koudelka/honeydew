defmodule FailInitOnceWorker do
  def init(test_process) do
    send test_process, :init_ran

    if Process.get(:already_failed) do
      {:ok, :state}
    else
      Process.put(:already_failed, true)
      raise "intentional init failure"
    end
  end
end
