defmodule Worker do
  use Honeydew

  def init(_) do
    {:ok, :state_here}
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

  def many_arguments(a, b, c, _state) do
    a <> b <> c
  end

  def one_argument(a, _state) do
    a
  end
end

defmodule SendBack do
  use Honeydew

  def init(to) do
    {:ok, to}
  end

  def send(to) do
    send(to, :hi)
  end
end

ExUnit.start()
