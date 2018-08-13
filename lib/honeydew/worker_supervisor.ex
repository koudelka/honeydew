defmodule Honeydew.WorkerSupervisor do
  use DynamicSupervisor, restart: :transient
  alias Honeydew.Worker

  def start_link([queue, %{shutdown: shutdown, num: num} = opts, queue_pid]) do
    {:ok, supervisor} = DynamicSupervisor.start_link(__MODULE__, [num], [])

    spec = Worker.child_spec([queue, opts, queue_pid], shutdown)
    Enum.each(1..num, fn _ ->
      {:ok, _} = DynamicSupervisor.start_child(supervisor, spec)
    end)

    {:ok, supervisor}
  end

  @impl true
  def init([num]) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: num)
  end
end
