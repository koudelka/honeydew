defmodule Honeydew.WorkQueueTest do
  use ExUnit.Case
  alias Honeydew.WorkQueue
  alias Honeydew.Worker

  setup do
    {:ok, work_queue} = Sender
    |> Honeydew.work_queue_name(:poolname)
    |> WorkQueue.start_link(3, 1)

    on_exit fn ->
      Process.exit(work_queue, :kill)
    end

    :ok
  end

  def work_queue_state do
    Sender
    |> Honeydew.work_queue_name(:poolname)
    |> :sys.get_state
  end

  def start_worker_linked do
    Worker.start_link(:poolname, Sender, [], 5)
  end

  def start_worker do
    Worker.start(:poolname, Sender, [], 5)
  end

  def queue_dummy_task, do: Sender.cast(:poolname, fn(_) -> :noop end)
  def queue_length, do: Sender.status(:poolname)[:queue]
  def backlog_length, do: Sender.status(:poolname)[:backlog]
  def num_waiting_workers, do: Sender.status(:poolname)[:waiting]

  test "add jobs to queue when no workers are available" do
    assert queue_length == 0

    queue_dummy_task
    queue_dummy_task
    queue_dummy_task

    assert queue_length == 3
  end

  test "immediately send jobs to a worker if one is available" do
    start_worker_linked

    assert queue_length == 0

    queue_dummy_task

    assert queue_length == 0
  end

  test "add worker to the waiting list if no jobs are available" do
    assert num_waiting_workers == 0

    start_worker_linked

    assert num_waiting_workers == 1
  end

  test "give worker a job from the queue when jobs are available" do
    task = fn(_) -> :timer.sleep(500) end
    Sender.cast(:poolname, task)

    assert queue_length == 1

    {:ok, worker} = start_worker_linked

    assert queue_length == 0

    assert work_queue_state.working[worker].task == task
  end

  test "shouldn't send jobs to workers that aren't alive" do
    {:ok, worker} = start_worker

    assert num_waiting_workers == 1

    Process.exit(worker, :kill)

    queue_dummy_task

    assert num_waiting_workers == 0
    assert queue_length == 1
  end

  test "should not run jobs while in 'suspend' mode" do
    start_worker_linked
    Sender.suspend(:poolname)
    queue_dummy_task
    assert num_waiting_workers == 1
    assert queue_length == 1
    :timer.sleep(100)
    assert queue_length == 1
  end

  test "run all suspended jobs once the pool is resumed" do
    start_worker_linked
    Sender.suspend(:poolname)

    assert queue_length == 0

    Sender.cast(:poolname, {:send_msg, [self, "honey"]})
    Sender.cast(:poolname, {:send_msg, [self, "i'm"]})
    Sender.cast(:poolname, {:send_msg, [self, "home"]})

    :timer.sleep(100)
    assert queue_length == 3

    Sender.resume(:poolname)
    assert_receive "honey"
    assert_receive "i'm"
    assert_receive "home"

    assert queue_length == 0
  end


  test "should recover jobs from workers that have crashed mid-process", c do
    test_process = self
    task = fn(_) -> send test_process, :hi; raise "ignore this error" end
    Sender.cast(:poolname, task)

    assert queue_length == 1
    assert num_waiting_workers == 0

    {:ok, _worker} = start_worker

    assert queue_length == 0
    assert num_waiting_workers == 0

    assert_receive :hi

    assert queue_length == 1
    assert num_waiting_workers == 0

    job = :queue.get(work_queue_state.queue)
    assert job.task == task
    assert job.failures == 1
  end

  test "should delay processing of a job after max failures", c do
    test_process = self
    task = fn(_) -> send test_process, :hi; raise "ignore this error" end
    Sender.cast(:poolname, task)

    {:ok, _worker} = start_worker
    :timer.sleep(10) # let the work queue process handle the failure
    assert_receive :hi
    assert queue_length == 1
    job = :queue.get(work_queue_state.queue)
    assert job.id == nil
    assert job.task == task
    assert job.failures == 1
    assert backlog_length == 0

    {:ok, _worker} = start_worker
    :timer.sleep(10) # let the work queue process handle the failure
    assert_receive :hi
    assert queue_length == 1
    job = :queue.get(work_queue_state.queue)
    assert job.id == nil
    assert job.task == task
    assert job.failures == 2
    assert backlog_length == 0

    {:ok, _worker} = start_worker
    :timer.sleep(10) # let the work queue process handle the failure
    assert_receive :hi
    assert queue_length == 0
    assert backlog_length == 1

    # the task is now on the backlog

    job = work_queue_state.backlog |> Set.to_list |> List.first
    assert job.id != nil
    assert job.task == task
    assert job.failures == 3

    {:ok, _worker} = start_worker

    :timer.sleep(500) # wait a moment to refute that the job hasn't run again
    refute_receive :hi
    :timer.sleep(2_000) # wait two more seconds for the delayed job to run
    assert_receive :hi
  end

end
