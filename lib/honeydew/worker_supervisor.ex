defmodule Honeydew.WorkerSupervisor do
  @moduledoc false

  use DynamicSupervisor, restart: :transient
  alias Honeydew.Worker

  def start_link([_queue, %{num: num}, _queue_pid] = opts) do
    {:ok, supervisor} = DynamicSupervisor.start_link(__MODULE__, [num], [])

    Enum.each(1..num, fn _ ->
      start_worker([supervisor | opts])
    end)

    {:ok, supervisor}
  end

  @impl true
  def init([num]) do
    DynamicSupervisor.init(strategy: :one_for_one, max_restarts: num)
  end

  def start_worker([supervisor | _rest] = opts) do
    spec = Worker.child_spec(opts)
    {:ok, _} = DynamicSupervisor.start_child(supervisor, spec)
  end
end
