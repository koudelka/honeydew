defmodule EctoPollQueueExample.Repo.Migrations.AddPrefixSchema do
  use Ecto.Migration

  if Mix.env() == :postgres do
    @prefix "theprefix"

    def up, do: execute("CREATE SCHEMA #{@prefix}")
    def down, do: execute("DROP SCHEMA #{@prefix}")
  else
    def change do
      # Cockroach does not support custom schemas
    end
  end
end
