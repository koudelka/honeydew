defmodule Stateless do
  @behaviour Honeydew.Worker
  import Honeydew.Progress

  def send_msg(to, msg) do
    send(to, msg)
  end

  def return(term) do
    term
  end

  def sleep(time) do
    Process.sleep(time)
  end

  def crash(pid) do
    send pid, :job_ran
    raise "ignore this crash"
  end

  def emit_progress(update) do
    progress(update)
    Process.sleep(500)
  end
end
