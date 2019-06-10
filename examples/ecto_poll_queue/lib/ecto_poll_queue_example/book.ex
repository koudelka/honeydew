defmodule EctoPollQueueExample.Book do
  use Ecto.Schema
  import Honeydew.EctoPollQueue.Schema
  alias Honeydew.EctoSource.ErlangTerm

  @primary_key false

  @ocr_queue :ocr

  schema "books" do
    field :author, :string, primary_key: true
    field :title, :string, primary_key: true

    field :from, ErlangTerm
    field :should_fail, :boolean

    honeydew_fields(@ocr_queue)

    timestamps()
  end

  def ocr_queue, do: @ocr_queue
end
