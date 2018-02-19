defmodule Stateful do
  @behaviour Honeydew.Worker
  def init(state) do
    {:ok, state}
  end

  def send_msg(to, msg, state) do
    send(to, {msg, state})
  end

  def return(term, state) do
    {term, state}
  end
end
