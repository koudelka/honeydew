# "Optical Character Recognition"

defmodule EctoPollQueueExample.OCRBook do
  alias EctoPollQueueExample.Repo
  alias EctoPollQueueExample.Book

  def run(primary_keys) do
    book = Repo.get_by(Book, primary_keys)

    if book.from do
      send(book.from, {:ocr_job_ran, primary_keys})
    end

    if book.should_fail do
      raise "ocr's totally busted dude!"
    end
  end
end
