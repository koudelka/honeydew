defmodule Honeydew.Application do
  @moduledoc false

  alias Honeydew.Queues
  alias Honeydew.Workers
  alias Honeydew.ProcessGroupScopeSupervisor

  use Application

  def start(_type, _args) do
    children = [
      {Queues, []},
      {Workers, []},
      {ProcessGroupScopeSupervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Honeydew.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
