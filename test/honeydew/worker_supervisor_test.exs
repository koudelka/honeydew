defmodule Honeydew.WorkerSupervisorTest do
  use ExUnit.Case, async: true

  alias Honeydew.WorkerSupervisor

  setup do
    pool = :erlang.unique_integer
    Honeydew.create_groups(pool)

    on_exit fn ->
      Honeydew.delete_groups(pool)
    end

    [pool: pool]
  end

  test "starts the correct number of workers", %{pool: pool} do
    {:ok, supervisor} =
      WorkerSupervisor.start_link(pool, Stateful, [:state_here], 7, 5, 10_000)

    assert supervisor |> Supervisor.which_children |> Enum.count == 7
  end

  test "crashes when the worker module does not exist", %{pool: pool} do
    Process.flag(:trap_exit, true)

    assert {:error, {:shutdown, {:failed_to_start_child, _, _}}} =
      WorkerSupervisor.start_link(pool, DoesNotExist, [], 7, 5, 10_000)
  end
end
