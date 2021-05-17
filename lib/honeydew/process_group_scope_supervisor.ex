#
# Dynamic supervision of :pg scopes (one per queue).
#
defmodule Honeydew.ProcessGroupScopeSupervisor do
  @moduledoc false

  use DynamicSupervisor

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(extra_args) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: extra_args)
  end

  def start_scope(name) do
    child_spec = %{
      id: name,
      start: {:pg, :start_link, [name]}
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
end
