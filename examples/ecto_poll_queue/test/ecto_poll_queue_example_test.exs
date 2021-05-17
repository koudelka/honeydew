defmodule EctoPollQueueExampleTest do
  use ExUnit.Case, async: false
  alias EctoPollQueueExample.Repo
  alias EctoPollQueueExample.Photo
  alias EctoPollQueueExample.User
  alias Honeydew.Job
  alias Honeydew.EctoSource
  alias Honeydew.EctoSource.State
  alias Honeydew.PollQueue.State, as: PollQueueState
  alias Honeydew.Queue.State, as: QueueState
  alias Honeydew.Processes

  @moduletag :capture_log

  setup do
    Honeydew.resume(User.notify_queue())
    Honeydew.resume(Photo.classify_queue())
    Repo.delete_all(Photo)
    Repo.delete_all(User)
    :ok
  end

  test "automatically enqueues when a new row is saved" do
    {:ok, %Photo{id: id}} = %Photo{} |> Repo.insert()
    Process.sleep(2_000)

    %Photo{
      tag: tag,
      honeydew_classify_photos_lock: lock,
      honeydew_classify_photos_private: private
    } = Repo.get(Photo, id)

    assert is_binary(tag)
    # clears lock
    assert is_nil(lock)
    # shouldn't be populated, as the job never failed
    assert is_nil(private)
  end

  test "status/1" do
    {:ok, _} = %User{from: self(), sleep: 3_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), sleep: 3_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), sleep: 3_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), should_fail: true} |> Repo.insert()
    Process.sleep(1_000)
    Honeydew.suspend(User.notify_queue())

    {:ok, _} = %User{from: self(), sleep: 3_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), sleep: 3_000} |> Repo.insert()

    assert %{queue: %{count: 6,
                      abandoned: 0,
                      ready: 2,
                      in_progress: 3,
                      delayed: 1,
                      stale: 0}} = Honeydew.status(User.notify_queue())
  end

  test "filter/2 abandoned" do
    {:ok, _} = %Photo{from: self(), sleep: 10_000} |> Repo.insert()
    {:ok, _} = %Photo{from: self(), sleep: 10_000} |> Repo.insert()
    {:ok, _} = %Photo{from: self(), sleep: 10_000} |> Repo.insert()

    failed_ids =
      Enum.map(1..2, fn _ ->
        {:ok, %Photo{id: failed_id}} = %Photo{from: self(), should_fail: true} |> Repo.insert()
        failed_id
      end)
      |> Enum.sort

    Process.sleep(1000)
    Honeydew.suspend(Photo.classify_queue())
    {:ok, _} = %Photo{from: self(), sleep: 1_000} |> Repo.insert()

    assert failed_jobs = Honeydew.filter(Photo.classify_queue(), :abandoned)

    ids =
      Enum.map(failed_jobs, fn %Job{private: [id: id], queue: queue} ->
        assert queue == Photo.classify_queue
        id
      end)
      |> Enum.sort

    assert ids == failed_ids
  end

  test "cancel/2" do
    Honeydew.suspend(User.notify_queue())
    {:ok, %User{id: id}} = %User{from: self()} |> Repo.insert()
    {:ok, %User{id: cancel_id}} = %User{from: self()} |> Repo.insert()

    Honeydew.cancel(cancel_id, User.notify_queue())

    Honeydew.resume(User.notify_queue())
    assert_receive {:notify_job_ran, ^id}, 1_000
    refute_receive {:notify_job_ran, ^cancel_id, 500}
  end

  test "resets stale jobs" do
    original_state = get_source_state(User.notify_queue())

    update_source_state(User.notify_queue(), fn state ->
      %State{state | stale_timeout: 0}
    end)

    {:ok, _user} = %User{from: self(), sleep: 2_000} |> Repo.insert()

    Process.sleep(1_500)

    assert %{queue: %{stale: 1, ready: 0}} = Honeydew.status(User.notify_queue())

    User.notify_queue()
    |> Processes.get_queue()
    |> send(:__reset_stale__)

    assert %{queue: %{stale: 0, ready: 1}} = Honeydew.status(User.notify_queue())

    update_source_state(User.notify_queue(), fn _state ->
      original_state
    end)
  end

  test "support inter-job persistent state (retry count, etc)" do
    {:ok, %Photo{id: id}} = %Photo{from: self(), should_fail: true} |> Repo.insert()

    Process.sleep(1_000)
    assert_receive {:classify_job_ran, ^id}

    Process.sleep(1_000)
    assert_receive {:classify_job_ran, ^id}

    Process.sleep(1_000)

    %Photo{
      tag: tag,
      honeydew_classify_photos_lock: lock,
      honeydew_classify_photos_private: private
    } = Repo.get(Photo, id)

    # job never ran successfully
    assert is_nil(tag)
    assert lock == EctoSource.abandoned()
    # cleared when job is abandonded
    assert is_nil(private)
  end

  test "delay via nack" do
    {:ok, %User{id: id}} = %User{from: self(), should_fail: true} |> Repo.insert()

    delays =
      Enum.map(0..3, fn _ ->
        receive do
          {:notify_job_ran, ^id} ->
            DateTime.utc_now()
        end
      end)
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.map(fn [a, b] -> DateTime.diff(b, a) end)

    # 3^0 - 1 -> 0 sec delay
    # 3^1 - 1 -> 2 sec delay
    # 3^2 - 1 -> 8 sec delay
    assert_in_delta Enum.at(delays, 0), 0, 1
    assert_in_delta Enum.at(delays, 1), 2, 1
    assert_in_delta Enum.at(delays, 2), 8, 1
  end

  test "supports :run_if" do
    {:ok, %User{id: run_id}} = %User{from: self(), name: "darwin"} |> Repo.insert()
    {:ok, %User{id: dont_run_id}} = %User{from: self(), name: "dont run"} |> Repo.insert()
    {:ok, %User{id: run_id_1}} = %User{from: self(), name: "odo"} |> Repo.insert()

    Process.sleep(1_000)

    assert_receive {:notify_job_ran, ^run_id}
    refute_receive {:notify_job_ran, ^dont_run_id}
    assert_receive {:notify_job_ran, ^run_id_1}
  end

  test "hammer" do
    ids =
      Enum.map(1..2_000, fn _ ->
        {:ok, %Photo{id: id}} = %Photo{from: self()} |> Repo.insert()
        id
      end)

    Enum.each(ids, fn id ->
      assert_receive({:classify_job_ran, ^id}, 400)
    end)

    refute_receive({:classify_job_ran, _}, 200)
  end

  defp get_source_state(queue) do
    %QueueState{private: %PollQueueState{source: {EctoSource, state}}} =
      queue
      |> Processes.get_queue()
      |> :sys.get_state

    state
  end

  defp update_source_state(queue, state_fn) do
    queue
    |> Processes.get_queue()
    |> :sys.replace_state(fn %QueueState{private: %PollQueueState{source: {EctoSource, state}} = poll_queue_state} = queue_state ->
      %QueueState{queue_state |
                  private: %PollQueueState{poll_queue_state |
                                           source: {EctoSource, state_fn.(state)}}}
    end)
  end
end
