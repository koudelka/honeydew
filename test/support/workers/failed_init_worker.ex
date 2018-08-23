defmodule FailedInitWorker do
  def init(test_process) do
    Process.put(:test_process, test_process)
    send test_process, {:init, self()}

    receive do
      :raise ->
        raise "init failed"
      :throw ->
        throw "init failed"
      :ok ->
        {:ok, nil}
    end
  end

  def failed_init do
    :test_process
    |> Process.get
    |> send(:failed_init_ran)

    Honeydew.reinitialize_worker()
  end
end
