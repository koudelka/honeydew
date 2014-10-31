defmodule Honeydew.JobListTest do
  use ExUnit.Case
  alias Honeydew.JobList
  alias Honeydew.Honey

  setup do
    Application.stop(:honeydew)
    Application.start(:honeydew)

    {:ok, job_list} = JobList.start_link(Worker, 3)
    {:ok, job_list: job_list}
  end

  def state(c) do
    :sys.get_state(c[:job_list])
  end

  def queue_dummy_task, do: Worker.cast(fn(_) -> :noop end)
  def backlog_length, do: JobList.backlog_length(Honeydew.job_list(Worker))
  def num_waiting_honeys, do: JobList.num_waiting_honeys(Honeydew.job_list(Worker))

  test "add jobs to backlog when no honey are available" do
    assert backlog_length == 0

    queue_dummy_task
    queue_dummy_task
    queue_dummy_task

    assert backlog_length == 3
  end

  test "immediately send jobs to a honey if one is available" do
    Honey.start_link(Worker)

    assert backlog_length == 0

    queue_dummy_task

    assert backlog_length == 0
  end

  test "add honey to the waiting list if no jobs are available" do
    assert num_waiting_honeys == 0

    Honey.start_link(Worker)

    assert num_waiting_honeys == 1
  end

  test "give honey a job from the backlog when jobs are available", c do
    task = fn(_) -> :timer.sleep(500) end
    Worker.cast(task)

    assert backlog_length == 1

    {:ok, honey} = Honey.start_link(Worker)

    assert backlog_length == 0

    assert state(c).working[honey].task == task
  end

  test "shouldn't send jobs to honeys that aren't alive" do
    # normal start_link would link to the test process and crash it when Process.exit is called
    {:ok, honey} = Honey.start( Worker)

    assert num_waiting_honeys == 1

    Process.exit(honey, :kill)

    queue_dummy_task

    assert num_waiting_honeys == 0
    assert backlog_length == 1
  end

  test "should recover jobs from honeys that have crashed mid-process", c do
    task = fn(_) -> :timer.sleep(500) end
    Worker.cast(task)

    assert backlog_length == 1

    {:ok, honey} = Honey.start(Worker)

    assert backlog_length == 0

    Process.exit(honey, :kill)

    assert num_waiting_honeys == 0
    assert backlog_length == 1

    job = :queue.get(state(c).jobs)
    assert job.task == task
    assert job.failures == 1
  end

  test "should stop trying to process a job after max failures", c do
    task = fn(_) -> :timer.sleep(500) end
    Worker.cast(task)

    {:ok, honey} = Honey.start(Worker)
    Process.exit(honey, :kill)
    :timer.sleep(10) # let the job list handle the failure
    assert backlog_length == 1
    job = :queue.get(state(c).jobs)
    assert job.task == task
    assert job.failures == 1

    {:ok, honey} = Honey.start(Worker)
    Process.exit(honey, :kill)
    :timer.sleep(10) # let the job list handle the failure
    assert backlog_length == 1
    job = :queue.get(state(c).jobs)
    assert job.task == task
    assert job.failures == 2

    {:ok, honey} = Honey.start(Worker)
    Process.exit(honey, :kill)
    :timer.sleep(10) # let the job list handle the failure
    assert backlog_length == 0
  end

end
