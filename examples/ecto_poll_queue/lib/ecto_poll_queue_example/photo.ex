defmodule EctoPollQueueExample.Photo do
  use Ecto.Schema
  import Honeydew.EctoPollQueue.Schema
  alias Honeydew.EctoSource.ErlangTerm

  if Mix.env == :cockroach do
    @primary_key {:id, :binary_id, autogenerate: false, read_after_writes: true}
    @foreign_key_type :binary_id
  else
    @primary_key {:id, :binary_id, autogenerate: true}
  end

  @classify_queue :classify_photos

  schema "photos" do
    field(:tag)
    field(:should_fail, :boolean)
    field(:sleep, :integer)
    field(:from, ErlangTerm)

    honeydew_fields(@classify_queue)

    timestamps()
  end

  def classify_queue, do: @classify_queue
end
