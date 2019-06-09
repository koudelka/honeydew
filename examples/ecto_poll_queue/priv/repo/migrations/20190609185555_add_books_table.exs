defmodule EctoPollQueueExample.Repo.Migrations.AddBooksTable do
  use Ecto.Migration

  import Honeydew.EctoPollQueue.Migration
  import EctoPollQueueExample.Book, only: [ocr_queue: 0]

  alias Honeydew.EctoSource.ErlangTerm

  def change do
    create table(:books, primary_key: false) do
      add :author, :string, primary_key: true
      add :title, :string, primary_key: true
      add :from, ErlangTerm.type()
      add :should_fail, :boolean

      if Mix.env == :cockroach do
        honeydew_fields(ocr_queue(), database: :cockroachdb)
      else
        honeydew_fields(ocr_queue())
      end

      timestamps()
    end
    honeydew_indexes(:books, ocr_queue())
  end
end
