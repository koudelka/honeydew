defmodule Sender do
  use Honeydew

  def init(state) do
    {:ok, state}
  end

  def send_hi(state) do
    send(state, :hi)
  end

  def send_msg(to, msg, _state) do
    send(to, msg)
  end

  def send_state(to, state) do
    send(to, state)
  end

  def state(state) do
    state
  end

  def one_argument(a, _state) do
    a
  end
end

defmodule BadInit do
  def init(_) do
    :bad
  end
end

defmodule RaiseOnInit do
  def init(_) do
    raise "bad"
  end
end

defmodule LinkDiesOnInit do
  def init(_) do
    spawn_link fn -> :born_to_die end
  end
end

ExUnit.start()
