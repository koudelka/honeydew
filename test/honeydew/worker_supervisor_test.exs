defmodule Honeydew.WorkerSupervisorTest do
  use ExUnit.Case, async: true

  setup do
    pool = :erlang.unique_integer

    Honeydew.create_groups(pool)

    {:ok, supervisor} = Honeydew.WorkerSupervisor.start_link(pool, %{ma: {Stateful, [:state_here]}, num: 7, init_retry: 5, shutdown: 10_000}, nil)

    # on_exit fn ->
    #   Supervisor.stop(supervisor)
    #   Honeydew.delete_groups(pool)
    # end

    [supervisor: supervisor]
  end

  test "starts the correct number of workers", %{supervisor: supervisor} do
    assert supervisor |> Supervisor.which_children |> Enum.count == 7
  end
end
