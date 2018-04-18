defmodule EctoPollQueueExample.User do
  use Ecto.Schema
  import Honeydew.EctoPollQueue.Schema
  alias Honeydew.EctoSource.ErlangTerm

  @primary_key {:id, :binary_id, autogenerate: false, read_after_writes: true}
  @foreign_key_type :binary_id

  @notify_queue :notify_user

  schema "users" do
    field(:name)
    field(:should_fail, :boolean)
    field(:sleep, :integer)
    field(:from, ErlangTerm)

    honeydew_fields(@notify_queue)

    timestamps()
  end

  def honeydew_task(id, _queue) do
    {:run, [id]}
  end

  def notify_queue, do: @notify_queue
end
