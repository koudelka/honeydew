defmodule EctoPollQueueExample.ClassifyPhoto do
  alias EctoPollQueueExample.Photo
  alias EctoPollQueueExample.Repo

  def run(id) do
    photo = Repo.get(Photo, id)

    if photo.sleep do
      Process.sleep(photo.sleep)
    end

    if photo.from do
      send(photo.from, {:classify_job_ran, id})
    end

    if photo.should_fail do
      raise "classifier's totally busted dude!"
    end

    tag = Enum.random(["newt", "ripley", "jonesey", "xenomorph"])

    photo
    |> Ecto.Changeset.change(%{tag: tag})
    |> Repo.update!()
  end
end
