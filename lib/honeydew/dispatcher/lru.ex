defmodule Honeydew.Dispatcher.LRU do
  @moduledoc false

  # TODO: docs

  def init do
    {:ok, {:queue.new, MapSet.new}}
  end

  def available?({free, _busy}) do
    !:queue.is_empty(free)
  end

  def check_in(worker, {free, busy}) do
    {:queue.in(worker, free), MapSet.delete(busy, worker)}
  end

  def check_out(_job, {free, busy}) do
    case :queue.out(free) do
      {{:value, worker}, free} ->
        {worker, {free, MapSet.put(busy, worker)}}
      {:empty, _free} ->
        {nil, {free, busy}}
    end
  end

  def remove(worker, {free, busy}) do
    {:queue.filter(&(&1 != worker), free), MapSet.delete(busy, worker)}
  end

  def known?(worker, {free, busy}) do
    :queue.member(worker, free) || MapSet.member?(busy, worker)
  end
end
