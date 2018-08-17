defmodule EctoPollQueueExampleTest do
  use ExUnit.Case, async: false
  alias EctoPollQueueExample.Repo
  alias EctoPollQueueExample.Photo
  alias EctoPollQueueExample.User
  alias Honeydew.EctoSource
  alias Honeydew.Job

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
    {:ok, _} = %User{from: self(), sleep: 2_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), sleep: 2_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), sleep: 2_000} |> Repo.insert()
    {:ok, _} = %User{from: self(), should_fail: true} |> Repo.insert()
    Process.sleep(1_000)
    Honeydew.suspend(User.notify_queue())

    {:ok, _} = %User{from: self(), sleep: 1_000} |> Repo.insert()

    assert %{queue: %{abandoned: 1, count: 5, in_progress: 3}} =
             Honeydew.status(User.notify_queue())
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
      Enum.map(failed_jobs, fn %Job{private: id, queue: queue} ->
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
    assert_receive {:notify_job_ran, ^id}
    refute_receive {:notify_job_ran, ^cancel_id, 500}
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
end
