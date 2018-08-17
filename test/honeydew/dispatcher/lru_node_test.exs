defmodule Honeydew.Dispatcher.LRUNodeTest do
  use ExUnit.Case, async: true
  alias Honeydew.Dispatcher.LRUNode

  setup do
    {:ok, state} = LRUNode.init

    state = LRUNode.check_in({"a", :a}, state)
    state = LRUNode.check_in({"a1", :a}, state)
    state = LRUNode.check_in({"b", :b}, state)
    state = LRUNode.check_in({"b1", :b}, state)
    state = LRUNode.check_in({"c", :c}, state)
    state = LRUNode.check_in({"c1", :c}, state)
    state = LRUNode.check_in({"d", :d}, state)

    [state: state]
  end

  test "cycle through least recently used node", %{state: state} do
    assert LRUNode.available?(state)

    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"a", :a}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"b", :b}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"c", :c}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"d", :d}

    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"a1", :a}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"b1", :b}
    {worker, _state} = LRUNode.check_out(nil, state)
    assert worker == {"c1", :c}
  end

  test "check_out/2 gives nil when none available", %{state: state} do
    {_worker, state} = LRUNode.check_out(nil, state)
    {_worker, state} = LRUNode.check_out(nil, state)
    {_worker, state} = LRUNode.check_out(nil, state)
    {_worker, state} = LRUNode.check_out(nil, state)
    {_worker, state} = LRUNode.check_out(nil, state)
    {_worker, state} = LRUNode.check_out(nil, state)
    {_worker, state} = LRUNode.check_out(nil, state)
    {worker, state} = LRUNode.check_out(nil, state)

    assert worker == nil
    refute LRUNode.available?(state)
  end

  test "removes workers", %{state: state} do
    state = LRUNode.remove({"b", :b}, state)
    state = LRUNode.remove({"d", :d}, state)

    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"a", :a}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"b1", :b}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"c", :c}

    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"a1", :a}
    {worker, state} = LRUNode.check_out(nil, state)
    assert worker == {"c1", :c}

    refute LRUNode.available?(state)
  end

  test "known?/2", %{state: state} do
    assert LRUNode.known?({"a", :a}, state)
    refute LRUNode.known?({"z", :z}, state)
  end
end
