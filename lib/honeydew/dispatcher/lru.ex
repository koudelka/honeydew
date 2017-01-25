defmodule Honeydew.Dispatcher.LRU do
  require Logger

  # TODO: docs

  def init do
    {:ok, :queue.new}
  end

  def available?(free) do
    :queue.len(free) > 0
  end

  def check_in(worker, free) do
    Logger.debug "[Honeydew] #{inspect self()} checked in worker #{inspect worker}"
    :queue.in(worker, free)
  end

  def check_out(_job, free) do
    case :queue.out(free) do
      {{:value, worker}, free} ->
        Logger.debug "[Honeydew] Queue #{inspect self()} checked out worker #{inspect worker}"
        {worker, free}
      {:empty, _free} ->
        Logger.debug "[Honeydew] Queue #{inspect self()} is out of workers"
        {nil, free}
    end
  end

  def remove(worker, free) do
    Logger.debug "[Honeydew] Queue #{inspect self()} removing worker #{inspect worker}"
    :queue.filter(&(&1 != worker), free)
  end
end
