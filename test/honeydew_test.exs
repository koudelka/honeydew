defmodule HoneydewTest do
  use ExUnit.Case

  setup do
    Application.stop(:honeydew)
    Application.start(:honeydew)
  end

  test "home_supervisor/1" do
    assert Honeydew.home_supervisor(Worker) == Honeydew.Worker.HomeSupervisor
  end

  test "job_list/1" do
    assert Honeydew.job_list(Worker) == Honeydew.Worker.JobList
  end

  test "honey_supervisor/1" do
    assert Honeydew.honey_supervisor(Worker) == Honeydew.Worker.HoneySupervisor
  end


  test "start_pool/2 should fail when the honey module doesn't exist" do
    assert_raise RuntimeError, ~s(Honeydew can't find the worker module named "Elixir.NotAModule"), fn ->
      Honeydew.start_pool(NotAModule, [], [])
    end
  end

  test "start_pool/2 starts a JobList and HoneySupervisor with a default of ten Honeys" do
    {:ok, home_supervisor} = Honeydew.start_pool(Worker, [], [])
    assert [{Honeydew.HoneySupervisor, honey_sup_pid, :supervisor, _},
            {Honeydew.JobList,                     _, :worker    , _}] = Supervisor.which_children(home_supervisor)

    honey_supervisor_children = Supervisor.which_children(honey_sup_pid)
    assert Enum.count(honey_supervisor_children) == 10
  end

end
