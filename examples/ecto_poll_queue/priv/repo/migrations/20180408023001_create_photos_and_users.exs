defmodule EctoPollQueue.Repo.Migrations.CreatePhotosAndUsers do
  use Ecto.Migration
  use Honeydew.EctoSource
  import EctoPollQueue.User, only: [notify_queue: 0]
  import EctoPollQueue.Photo, only: [classify_queue: 0]
  alias Honeydew.EctoSource.ErlangTerm

  def change do
    create table(:photos, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :tag, :string
      add :should_fail, :boolean
      add :sleep, :integer
      add :from, ErlangTerm.type()

      honeydew_migration_fields(classify_queue())
      timestamps()
    end
    honeydew_migration_indexes(:photos, classify_queue())

    create table(:users, primary_key: false) do
      add :id, :uuid, primary_key: true, default: fragment("gen_random_uuid()")

      add :name, :string
      add :should_fail, :boolean
      add :sleep, :integer
      add :from, ErlangTerm.type()

      honeydew_migration_fields(notify_queue())
      timestamps()
    end
    honeydew_migration_indexes(:users, notify_queue())
  end
end
