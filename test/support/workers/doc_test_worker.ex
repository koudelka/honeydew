defmodule DocTestWorker do
  def ping(_ip) do
    Process.sleep(1000)
    :pong
  end
end
