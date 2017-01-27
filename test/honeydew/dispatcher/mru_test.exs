defmodule Honeydew.Dispatcher.MRUTest do
  use ExUnit.Case, async: true
  alias Honeydew.Dispatcher.MRU

  setup do
    {:ok, state} = MRU.init

    state = MRU.check_in("a", state)
    state = MRU.check_in("b", state)
    state = MRU.check_in("c", state)

    [state: state]
  end

  test "enqueue/dequeue most recently used", %{state: state} do
    assert MRU.available?(state)

    {worker, state} = MRU.check_out(nil, state)
    assert worker == "c"
    {worker, state} = MRU.check_out(nil, state)
    assert worker == "b"
    {worker, _state} = MRU.check_out(nil, state)
    assert worker == "a"
  end

  test "check_out/2 gives nil when none available", %{state: state} do
    {_worker, state} = MRU.check_out(nil, state)
    {_worker, state} = MRU.check_out(nil, state)
    {_worker, state} = MRU.check_out(nil, state)

    {worker, state} = MRU.check_out(nil, state)
    assert worker == nil

    refute MRU.available?(state)
  end

  test "removes workers", %{state: state} do
    state = MRU.remove("b", state)

    {worker, state} = MRU.check_out(nil, state)
    assert worker == "c"
    {worker, state} = MRU.check_out(nil, state)
    assert worker == "a"

    {worker, _state} = MRU.check_out(nil, state)
    assert worker == nil
  end
end
