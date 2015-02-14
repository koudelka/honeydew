defmodule Honeydew.HoneySupervisor do
  alias Honeydew.Honey

  def start_link(honey_module, honey_init_args, num_workers, init_retry_secs) do
    import Supervisor.Spec

    children = [
      worker(Honey, [], restart: :transient)
    ]

    opts = [strategy: :simple_one_for_one, name: Honeydew.honey_supervisor(honey_module)]

    {:ok, honey_supervisor} = Supervisor.start_link(children, opts)

    # let the honey supervisor finish starting, then try to start children asynchronously.
    Enum.each(1..num_workers, fn(_) ->
      :timer.apply_after(0, __MODULE__, :start_child, [honey_module, honey_init_args, init_retry_secs])
    end)

    {:ok, honey_supervisor}
  end

  @doc "Starts a new worker for the given `honey_module` with the arguments `honey_init_args` and respawn delay `init_retry_secs`"
  def start_child(honey_module, honey_init_args, init_retry_secs) do
    honey_supervisor = Honeydew.honey_supervisor(honey_module)
    Supervisor.start_child(honey_supervisor, [honey_module, honey_init_args, init_retry_secs])
  end
end
