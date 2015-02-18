defmodule Honeydew.JobListTest do
  use ExUnit.Case
  alias Honeydew.JobList
  alias Honeydew.Honey

  setup do
    Application.stop(:honeydew)
    Application.start(:honeydew)

    {:ok, job_list} = JobList.start_link(Worker, 3, 1)
    {:ok, job_list: job_list}
  end

  def state(c) do
    :sys.get_state(c[:job_list])
  end

  def queue_dummy_task, do: Worker.cast(fn(_) -> :noop end)
  def queue_length, do: Worker.status[:jobs]
  def backlog_length, do: Worker.status[:backlog]
  def num_waiting_honeys, do: Worker.status[:waiting]

  test "add jobs to queue when no honeys are available" do
    assert queue_length == 0

    queue_dummy_task
    queue_dummy_task
    queue_dummy_task

    assert queue_length == 3
  end

  test "immediately send jobs to a honey if one is available" do
    Honey.start_link(Worker)

    assert queue_length == 0

    queue_dummy_task

    assert queue_length == 0
  end

  test "add honey to the waiting list if no jobs are available" do
    assert num_waiting_honeys == 0

    Honey.start_link(Worker)

    assert num_waiting_honeys == 1
  end

  test "give honey a job from the queue when jobs are available", c do
    task = fn(_) -> :timer.sleep(500) end
    Worker.cast(task)

    assert queue_length == 1

    {:ok, honey} = Honey.start_link(Worker)

    assert queue_length == 0

    assert state(c).working[honey].task == task
  end

  test "shouldn't send jobs to honeys that aren't alive" do
    # normal start_link would link to the test process and crash it when Process.exit is called
    {:ok, honey} = Honey.start( Worker)

    assert num_waiting_honeys == 1

    Process.exit(honey, :kill)

    queue_dummy_task

    assert num_waiting_honeys == 0
    assert queue_length == 1
  end

  test "should recover jobs from honeys that have crashed mid-process", c do
    task = fn(_) -> raise "ignore this error" end
    Worker.cast(task)

    assert queue_length == 1

    {:ok, _honey} = Honey.start(Worker)

    assert queue_length == 0
    assert num_waiting_honeys == 0
    assert queue_length == 1

    job = :queue.get(state(c).jobs)
    assert job.task == task
    assert job.failures == 1
  end

  test "should delay processing of a job after max failures", c do
    testing_process = self
    task = fn(_) -> send testing_process, :hi; raise "ignore this error" end
    Worker.cast(task)

    {:ok, _honey} = Honey.start(Worker)
    :timer.sleep(10) # let the job list handle the failure
    assert_receive :hi
    assert queue_length == 1
    job = :queue.get(state(c).jobs)
    assert job.id == nil
    assert job.task == task
    assert job.failures == 1
    assert backlog_length == 0

    {:ok, _honey} = Honey.start(Worker)
    :timer.sleep(10) # let the job list handle the failure
    assert_receive :hi
    assert queue_length == 1
    job = :queue.get(state(c).jobs)
    assert job.id == nil
    assert job.task == task
    assert job.failures == 2
    assert backlog_length == 0

    {:ok, _honey} = Honey.start(Worker)
    :timer.sleep(10) # let the job list handle the failure
    assert_receive :hi
    assert queue_length == 0
    assert backlog_length == 1

    {:ok, _honey} = Honey.start(Worker)
    # the job has now been placed on the backlog
    job = state(c).backlog |> Set.to_list |> List.first
    assert job.id != nil
    assert job.task == task
    assert job.failures == 3

    :timer.sleep(500) # wait a moment to refute that the job hasn't run again
    refute_receive :hi
    :timer.sleep(2_000) # wait two more seconds for the delayed job to run
    assert_receive :hi
  end

end
