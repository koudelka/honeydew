defmodule Honeydew.Workers do
  alias Honeydew.{WorkerGroupsSupervisor, WorkerStarter}

  @type queue_name :: Honeydew.queue_name()
  @type mod_or_mod_args :: Honeydew.mod_or_mod_args()
  @type worker_spec_opt :: Honeydew.worker_spec_opt()

  @doc """
  Creates a supervision spec for workers.

  `queue` is the name of the queue that the workers pull jobs from.

  `module` is the module that the workers in your queue will use. You may also
  provide `c:Honeydew.Worker.init/1` args with `{module, args}`.

  You can provide any of the following `opts`:

  - `num`: the number of workers to start. Defaults to `10`.

  - `init_retry`: the amount of time, in seconds, to wait before respawning
     a worker whose `c:Honeydew.Worker.init/1` function failed. Defaults to `5`.

  - `shutdown`: if a worker is in the middle of a job, the amount of time, in
     milliseconds, to wait before brutally killing it. Defaults to `10_000`.

  - `supervisor_opts` options accepted by `Supervisor.Spec.supervisor/3`.

  - `nodes`: for :global queues, you can provide a list of nodes to stay
     connected to (your queue node and enqueuing nodes). Defaults to `[]`.

  For example:

  - `Honeydew.child_spec("my_awesome_queue", MyJobModule)`

  - `Honeydew.child_spec("my_awesome_queue", {MyJobModule, [key: "secret key"]}, num: 3)`

  - `Honeydew.child_spec({:global, "my_awesome_queue"}, MyJobModule, nodes: [:clientfacing@dax, :queue@dax])`
  """
  # @spec child_spec([queue_name, mod_or_mod_args, [worker_spec_opt]]) :: Supervisor.Spec.spec
  @spec child_spec([...]) :: Supervisor.Spec.spec
  def child_spec([queue, module_and_args]), do: child_spec([queue, module_and_args, []])

  def child_spec([queue, module_and_args | opts]) do
    {module, args} =
      case module_and_args do
        module when is_atom(module) -> {module, []}
        {module, args} -> {module, args}
      end

    supervisor_opts =
      opts
      |> Keyword.get(:supervisor_opts, [])
      |> Keyword.put_new(:restart, :permanent)
      |> Keyword.put_new(:shutdown, :infinity)
      |> Enum.into(%{})

    opts = %{
      ma: {module, args},
      num: opts[:num] || 10,
      init_retry: opts[:init_retry] || 5,
      shutdown: opts[:shutdown] || 10_000,
      nodes: opts[:nodes] || []
    }

    spec = %{
      id: {:worker, queue},
      start: {__MODULE__, :start_link, [queue, opts]}
    }

    Map.merge(spec, supervisor_opts)
  end


  def start_link(queue, %{nodes: nodes} = opts) do
    import Supervisor.Spec

    Honeydew.create_groups(queue)

    children = [supervisor(WorkerGroupsSupervisor, [queue, opts]),
                worker(WorkerStarter, [queue])]

    # if the worker groups supervisor shuts down due to too many groups
    # restarting (hits max intensity), we also want the WorkerStarter to die
    # so that it may restart the necessary worker groups when the groups
    # supervisor comes back up
    supervisor_opts = [strategy: :rest_for_one,
                       name: Honeydew.supervisor(queue, :worker_root)]

    queue
    |> case do
         {:global, _} -> children ++ [supervisor(Honeydew.NodeMonitorSupervisor, [queue, nodes])]
         _ -> children
       end
    |> Supervisor.start_link(supervisor_opts)
  end
end
