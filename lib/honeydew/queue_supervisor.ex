defmodule Honeydew.QueueSupervisor do

  def start_link(queue, module, args, num_queues, dispatcher, failure_mode, success_mode) do
    import Supervisor.Spec

    children = [
      worker(module, [queue, args, dispatcher, failure_mode, success_mode])
    ]

    opts = [strategy: :simple_one_for_one,
            name: Honeydew.supervisor(queue, :queue),
            # what would be sane settings here?
            # if a queue dies because it's trying to connect to a remote host,
            # should we delay the restart like with workers?
            max_restarts: num_queues,
            max_seconds: 5]

    {:ok, supervisor} = Supervisor.start_link(children, opts)

    # start up workers
    Enum.each(1..num_queues, fn _ ->
      {:ok, _} = Supervisor.start_child(supervisor, [])
    end)

    {:ok, supervisor}
  end

end
