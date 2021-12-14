defmodule CompoundKeysTest do
  use ExUnit.Case, async: false
  alias EctoPollQueueExample.Repo
  alias EctoPollQueueExample.Book
  alias Honeydew.EctoSource

  @moduletag :capture_log

  setup do
    Repo.delete_all(Book)
    :ok
  end

  test "automatically enqueues when a new row is saved" do
    author = "Yuval Noah Harari"
    title = "Sapiens"

    {:ok, %Book{}} = %Book{author: author, title: title, from: self()} |> Repo.insert()
    Process.sleep(2_000)

    keys = [author: author, title: title]

    %Book{
      honeydew_ocr_lock: lock,
      honeydew_ocr_private: private
    } = Repo.get_by(Book, keys)

    assert_receive {:ocr_job_ran, ^keys}, 1_000

    # clears lock
    assert is_nil(lock)
    # shouldn't be populated, as the job never failed
    assert is_nil(private)
  end

  test "cancel/2" do
    Honeydew.suspend(Book.ocr_queue())
    {:ok, %Book{}} = %Book{author: "Neil Stephenson", title: "Anathem", from: self()} |> Repo.insert()
    {:ok, %Book{}} = %Book{author: "Issac Asimov", title: "Rendezvous with Rama", from: self()} |> Repo.insert()

    cancel_keys = [author: "Issac Asimov", title: "Rendezvous with Rama"]
    Honeydew.cancel(cancel_keys, Book.ocr_queue())

    Honeydew.resume(Book.ocr_queue())
    assert_receive {:ocr_job_ran, [author: "Neil Stephenson", title: "Anathem"]}, 1_000
    refute_receive {:ocr_job_ran, ^cancel_keys, 500}
  end

  test "support inter-job persistent state (retry count, etc)" do
    {:ok, %Book{}} = %Book{author: "Hugh D. Young", title: "University Physics", from: self(), should_fail: true} |> Repo.insert()

    primary_keys = [author: "Hugh D. Young", title: "University Physics"]

    Process.sleep(1_000)
    assert_receive {:ocr_job_ran, ^primary_keys}, 1_000

    Process.sleep(1_000)
    assert_receive {:ocr_job_ran, ^primary_keys}, 1_000

    Process.sleep(1_000)

    %Book{
      honeydew_ocr_lock: lock,
      honeydew_ocr_private: private
    } = Repo.get_by(Book, primary_keys)

    # job never ran successfully
    assert lock == EctoSource.abandoned()
    # cleared when job is abandoned
    assert is_nil(private)
  end

  test "hammer" do
    keys =
      Enum.map(1..2_000, fn i ->
        author = "author_#{i}"
        title = "title_#{i}"

        {:ok, %Book{}} = %Book{author: author, title: title, from: self()} |> Repo.insert()
        [author: author, title: title]
      end)

    Enum.each(keys, fn key ->
      assert_receive({:ocr_job_ran, ^key}, 400)
    end)

    refute_receive({:ocr_job_ran, _}, 200)
  end
end
