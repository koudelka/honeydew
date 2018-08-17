defmodule Honeydew.Dispatcher.MRU do
  alias Honeydew.Dispatcher.LRU
  # TODO: docs

  defdelegate init, to: LRU
  defdelegate available?(state), to: LRU
  defdelegate check_out(job, state), to: LRU
  defdelegate remove(worker, state), to: LRU
  defdelegate known?(worker, state), to: LRU

  def check_in(worker, {free, busy}) do
    {:queue.in_r(worker, free), MapSet.delete(busy, worker)}
  end
end
