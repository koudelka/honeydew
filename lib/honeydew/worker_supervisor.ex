defmodule Honeydew.WorkerSupervisor do
  alias Honeydew.Worker

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, opts},
      type: :supervisor
    }
  end

  def start_link(queue, %{shutdown: _shutdown, init_retry: init_retry_secs, num: num} = opts, queue_pid) do
    opts = Enum.into(opts, %{restart: :transient})

    supervisor_opts = [
      strategy: :one_for_one,
      name: Honeydew.supervisor(queue, :worker),
      max_restarts: num,
      max_seconds: init_retry_secs,
      extra_arguments: [queue, opts, queue_pid]
    ]

    {:ok, supervisor} = DynamicSupervisor.start_link(supervisor_opts)

    start_workers(supervisor, num)

    {:ok, supervisor}
  end

  defp start_workers(_supervisor, 0), do: :noop

  defp start_workers(supervisor, num) do
    DynamicSupervisor.start_child(supervisor, {Worker, []})
    start_workers(supervisor, num - 1)
  end
end
