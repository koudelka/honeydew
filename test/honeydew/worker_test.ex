defmodule Honeydew.HoneyTest do
  use ExUnit.Case
  alias Honeydew.Worker
  alias Honeydew.Job

  def start_worker do
    # the worker's init is going to ask its work queue process to monitor it before asking for a job,
    # so we need to be able to receive that request and discard it (and not be blocking on Worker.start)
    test_process = self
    Task.async fn -> Worker.start_link(test_process, Sender, test_process, 5) end

    receive do
      {_, {worker, ref}, :monitor_me} -> GenServer.reply({worker, ref}, :ok)
                                         worker
    end
  end

  def send_job(worker, %Job{} = job) do
    receive do
      {:"$gen_call", {^worker, ref}, :job_please} -> GenServer.reply({worker, ref}, job)
    end
  end

  def send_job(worker, task) do
    send_job worker, %Job{task: task}
  end

  test "init/1 should tell its supervisor to ignore it if the worker module doesn't init properly" do
    defmodule RaiseOnInit do
      def init(_) do
        raise "bad"
      end
    end

    assert Worker.start_link(nil, RaiseOnInit, [], 5) == :ignore

    defmodule BadInit do
      def init(_) do
        :bad
      end
    end

    assert Worker.start_link(nil, BadInit, [], 5) == :ignore
  end

  test "should ask to be monitored, then ask for a job after starting" do
    worker = start_worker
    assert_receive {:"$gen_call", {^worker, _ref}, :job_please}
  end

  test "should ask for a job after completing the last one" do
    worker = start_worker
    test_process = self

    send_job(worker, fn(_) -> send(test_process, "honey") end)
    assert_receive "honey"

    send_job(worker, fn(_) -> send(test_process, "i'm") end)
    assert_receive "i'm"

    send_job(worker, fn(_) -> send(test_process, "home") end)
    assert_receive "home"
  end

  test "should accept funs, function names and {function, argument(s)} as tasks" do
    worker = start_worker
    test_process = self

    send_job(worker, :send_hi)
    assert_receive :hi

    send_job(worker, {:send_msg, [test_process, "honey"]})
    assert_receive "honey"

    send_job(worker, fn(_) -> send(test_process, "i'm home") end)
    assert_receive "i'm home"
  end

  test "should pass the worker's state to the task" do
    worker = start_worker
    test_process = self

    send_job(worker, {:send_state, [test_process]})
    assert_receive ^test_process # the test process' pid is the state in this case
  end

  test "should send the task's result if the job specified a 'from' (from GenServer.call)" do
    worker = start_worker
    test_process = self

    job = %Job{task: {:one_argument, [:hi_there]}, from: {test_process, :fake_ref}}
    send_job(worker, job)
    assert_receive {:fake_ref, :hi_there}
  end
end
