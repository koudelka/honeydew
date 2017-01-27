defmodule Honeydew.Dispatcher.LRUTest do
  use ExUnit.Case, async: true
  alias Honeydew.Dispatcher.LRU

  setup do
    {:ok, state} = LRU.init

    state = LRU.check_in("a", state)
    state = LRU.check_in("b", state)
    state = LRU.check_in("c", state)

    [state: state]
  end

  test "enqueue/dequeue least recently used", %{state: state} do
    assert LRU.available?(state)

    {worker, state} = LRU.check_out(nil, state)
    assert worker == "a"
    {worker, state} = LRU.check_out(nil, state)
    assert worker == "b"
    {worker, _state} = LRU.check_out(nil, state)
    assert worker == "c"
  end

  test "check_out/2 gives nil when none available", %{state: state} do
    {_worker, state} = LRU.check_out(nil, state)
    {_worker, state} = LRU.check_out(nil, state)
    {_worker, state} = LRU.check_out(nil, state)

    {worker, state} = LRU.check_out(nil, state)
    assert worker == nil

    refute LRU.available?(state)
  end

  test "removes workers", %{state: state} do
    state = LRU.remove("b", state)

    {worker, state} = LRU.check_out(nil, state)
    assert worker == "a"
    {worker, state} = LRU.check_out(nil, state)
    assert worker == "c"

    {worker, _state} = LRU.check_out(nil, state)
    assert worker == nil
  end
end
