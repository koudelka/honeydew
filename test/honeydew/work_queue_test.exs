defmodule Honeydew.WorkQueueTest do
  use ExUnit.Case
  alias Honeydew.WorkQueue
  alias Honeydew.Worker

  setup do
    {:ok, work_queue} = Sender
    |> Honeydew.work_queue_name(:poolname)
    |> WorkQueue.start_link(3, 1)

    {:ok, work_queue: work_queue}
  end

  def work_queue_state do
    Sender
    |> Honeydew.work_queue_name(:poolname)
    |> :sys.get_state
  end

  def start_worker do
    Worker.start_link(:poolname, Sender, [], 5)
  end

  def queue_dummy_task, do: Sender.cast(:poolname, fn(_) -> :noop end)
  def queue_length, do: Sender.status(:poolname)[:queue]
  # def backlog_length, do: Worker.status[:backlog]
  def num_waiting_workers, do: Sender.status(:poolname)[:waiting]

  test "add jobs to queue when no workers are available" do
    assert queue_length == 0

    queue_dummy_task
    queue_dummy_task
    queue_dummy_task

    assert queue_length == 3
  end

  test "immediately send jobs to a worker if one is available" do
    start_worker

    assert queue_length == 0

    queue_dummy_task

    assert queue_length == 0
  end

  test "add worker to the waiting list if no jobs are available" do
    assert num_waiting_workers == 0

    start_worker

    assert num_waiting_workers == 1
  end

  test "give worker a job from the queue when jobs are available" do
    task = fn(_) -> :timer.sleep(500) end
    Sender.cast(:poolname, task)

    assert queue_length == 1

    {:ok, worker} = start_worker

    assert queue_length == 0

    assert work_queue_state.working[worker].task == task
  end

  test "shouldn't send jobs to workers that aren't alive" do
    # start_worker uses start_link, which would bring down the test process when we Process.exit it
    {:ok, worker} = fn -> start_worker end |> Task.async |> Task.await

    assert num_waiting_workers == 1

    Process.exit(worker, :kill)

    queue_dummy_task

    assert num_waiting_workers == 0
    assert queue_length == 1
  end

  test "should not run jobs while in 'suspend' mode" do
    start_worker 
    Sender.suspend(:poolname)
    queue_dummy_task
    assert num_waiting_workers == 1
    assert queue_length == 1
    :timer.sleep(100)
    assert queue_length == 1
  end

  test "run all suspended jobs once the pool is resumed" do
    start_worker
    Sender.suspend(:poolname)
    queue_dummy_task
    queue_dummy_task
    queue_dummy_task
    assert queue_length == 3
    Sender.resume(:poolname)
    :timer.sleep(100)
    assert queue_length == 0   
  end
 

  # test "should recover jobs from honeys that have crashed mid-process", c do
  #   task = fn(_) -> raise "ignore this error" end
  #   Worker.cast(task)

  #   assert queue_length == 1

  #   {:ok, _honey} = Honey.start(Worker)

  #   assert queue_length == 0
  #   assert num_waiting_honeys == 0
  #   assert queue_length == 1

  #   job = :queue.get(state(c).jobs)
  #   assert job.task == task
  #   assert job.failures == 1
  # end

  # test "should delay processing of a job after max failures", c do
  #   testing_process = self
  #   task = fn(_) -> send testing_process, :hi; raise "ignore this error" end
  #   Worker.cast(task)

  #   {:ok, _honey} = Honey.start(Worker)
  #   :timer.sleep(10) # let the job list handle the failure
  #   assert_receive :hi
  #   assert queue_length == 1
  #   job = :queue.get(state(c).jobs)
  #   assert job.id == nil
  #   assert job.task == task
  #   assert job.failures == 1
  #   assert backlog_length == 0

  #   {:ok, _honey} = Honey.start(Worker)
  #   :timer.sleep(10) # let the job list handle the failure
  #   assert_receive :hi
  #   assert queue_length == 1
  #   job = :queue.get(state(c).jobs)
  #   assert job.id == nil
  #   assert job.task == task
  #   assert job.failures == 2
  #   assert backlog_length == 0

  #   {:ok, _honey} = Honey.start(Worker)
  #   :timer.sleep(10) # let the job list handle the failure
  #   assert_receive :hi
  #   assert queue_length == 0
  #   assert backlog_length == 1

  #   {:ok, _honey} = Honey.start(Worker)
  #   # the job has now been placed on the backlog
  #   job = state(c).backlog |> Set.to_list |> List.first
  #   assert job.id != nil
  #   assert job.task == task
  #   assert job.failures == 3

  #   :timer.sleep(500) # wait a moment to refute that the job hasn't run again
  #   refute_receive :hi
  #   :timer.sleep(2_000) # wait two more seconds for the delayed job to run
  #   assert_receive :hi
  # end

end
