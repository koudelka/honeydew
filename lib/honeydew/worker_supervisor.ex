defmodule Honeydew.WorkerSupervisor do
  use DynamicSupervisor
  alias Honeydew.Worker

  def start_link([queue, %{shutdown: shutdown, num: num} = opts, queue_pid]) do
    supervisor_opts = [name: Honeydew.supervisor(queue, :worker),]

    {:ok, supervisor} = DynamicSupervisor.start_link(__MODULE__, opts, supervisor_opts)

    Enum.each(1..num, fn _ ->
      spec = Worker.child_spec([queue, opts, queue_pid], shutdown)
      DynamicSupervisor.start_child(supervisor, spec)
    end)

    {:ok, supervisor}
  end

  @impl true
  def init(%{num: num, init_retry: init_retry_secs}) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: num,
      max_seconds: init_retry_secs
    )
  end
end
