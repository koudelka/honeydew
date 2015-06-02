defmodule HoneydewTest do
  use ExUnit.Case, async: false
  # pools register processes globally, so async: false

  test "work_queue_name/2" do
    assert Honeydew.work_queue_name(Sender, :poolname) == :"Elixir.Honeydew.Sender.poolname"
  end

  test "starts a correct supervision tree" do
    {:ok, supervisor} = Honeydew.Supervisor.start_link(:poolname, Sender, [:state_here], workers: 7)
    assert [{:worker_supervisor, worker_supervisor, :supervisor, _},
            {:work_queue,              _work_queue, :worker,     _}] = Supervisor.which_children(supervisor)

    assert worker_supervisor |> Supervisor.which_children |> Enum.count == 7
  end

  test "calls the worker module's init/1 and keeps it as state" do
    {:ok, _} = Honeydew.Supervisor.start_link(:poolname, Sender, :state_here)

    Sender.call(:poolname, {:send_state, [self]})
    assert_receive :state_here
  end

end
