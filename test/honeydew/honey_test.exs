defmodule Honeydew.HoneyTest do
  use ExUnit.Case
  alias Honeydew.JobList
  alias Honeydew.Honey

  setup do
    Application.stop(:honeydew)
    Application.start(:honeydew)

    {:ok, _job_list} = JobList.start_link(Worker, 3, 30)
    {:ok, _honey} = Honey.start_link(Worker, [], 0)

    :ok
  end

  def state(item) do
    :sys.get_state(item)
  end

  test "should call the honey's module's init/1 function and use it as state" do
    test_process = self

    Worker.cast(fn(state) -> send(test_process, state) end)

    assert_receive :state_here
  end

  test "init/1 should return an error if the honey module's init/1 raise an error" do
    defmodule RaiseOnInitWorker do
      def init(_) do
        raise "bad"
      end
    end

    {:ok, _job_list} = JobList.start_link(RaiseOnInitWorker, 3, 30)
    assert Honey.start(RaiseOnInitWorker) == :ignore
  end

  test "init/1 should return an error if the honey module's init/1 doesn't return {:ok, state}" do
    defmodule BadInitWorker do
      def init do
        :bad
      end
    end

    {:ok, _job_list} = JobList.start_link(BadInitWorker, 3, 30)
    assert Honey.start(BadInitWorker) == :ignore
  end

  test "should ask for a job after completing the last one" do
    test_process = self

    Worker.cast(fn(_) -> send(test_process, "honey") end)
    assert_receive "honey"

    Worker.cast(fn(_) -> send(test_process, "i'm") end)
    assert_receive "i'm"

    Worker.cast(fn(_) -> send(test_process, "home") end)
    assert_receive "home"
  end

  test "cast/1 should accept both funs, function names and {function, argument(s)} as tasks" do
    test_process = self

    Worker.cast(fn(_) -> send(test_process, "honey") end)
    assert_receive "honey"

    Worker.cast({:send_msg, [test_process, "i'm"]})
    assert_receive "i'm"

    {:ok, _job_list} = JobList.start_link(SendBack, 3, 30)
    {:ok, _honey} = Honey.start_link(SendBack, self, 0)

    SendBack.cast(:send)
    assert_receive :hi
  end

  test "should pass the honey's state to the task" do
    test_process = self

    Worker.cast(fn(state) -> send(test_process, state) end)
    assert_receive :state_here

    Worker.cast({:send_state, [test_process]})
    assert_receive :state_here
  end

  test "call/2 should return the result of the task" do
    assert Worker.call(&(&1)) == :state_here
    assert Worker.call(:state) == :state_here
    assert Worker.call({:one_argument, [:a]}) == :a
    assert Worker.call({:many_arguments, ["a", "b", "c"]}) == "abc"
  end
end
