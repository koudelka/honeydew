defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.Worker

  def start_link do
    import Supervisor.Spec

    children = [
      worker(Worker, [], restart: :transient)
    ]

    Supervisor.start_link(children, strategy: :simple_one_for_one)
  end
end
