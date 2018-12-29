if Code.ensure_loaded?(Ecto) do
  defmodule Honeydew.EctoSource.SQL.Cockroach do
    alias Honeydew.EctoSource
    alias Honeydew.EctoSource.SQL

    @behaviour SQL

    @impl true
    def integer_type do
      :bigint
    end

    @impl true
    def table_name(schema) do
      schema.__schema__(:source)
    end

    @impl true
    def ready do
      "CAST('#{SQL.far_in_the_past()}' AS TIMESTAMP)"
      |> time_in_msecs
      |> msecs_ago
    end

    @impl true
    def reserve(state) do
      "UPDATE #{state.table}
      SET #{state.lock_field} = #{now_msecs()}
      WHERE #{state.lock_field} BETWEEN 0 AND #{msecs_ago(state.stale_timeout)}
      ORDER BY #{state.lock_field}, #{state.key_field}
      LIMIT 1
      RETURNING #{state.key_field}, #{state.private_field}"
    end

    @impl true
    def cancel(state) do
      "UPDATE #{state.table}
      SET #{state.lock_field} = NULL
      WHERE
        id = $1
        AND #{state.lock_field} BETWEEN 0 AND #{msecs_ago(state.stale_timeout)}
      RETURNING #{state.lock_field}"
    end

    @impl true
    def status(state) do
      "SELECT COUNT(IF(#{state.lock_field} IS NOT NULL, 1, NULL)) AS count,
              COUNT(IF(#{state.lock_field} >= #{msecs_ago(state.stale_timeout)}, 1, NULL)) AS in_progress,
              COUNT(IF(#{state.lock_field} = #{EctoSource.abandoned()}, 1, NULL)) AS abandoned
      FROM #{state.table}"
    end

    @impl true
    def filter(state, :abandoned) do
      "SELECT id FROM #{state.table} WHERE #{state.lock_field} = #{EctoSource.abandoned()}"
    end

    defp msecs_ago(msecs) do
      "#{now_msecs()} - #{msecs}"
    end

    defp now_msecs do
      time_in_msecs("NOW()")
    end

    defp time_in_msecs(time) do
      "(EXTRACT('millisecond', (#{time})) + CAST((#{time}) AS INT) * 1000)"
    end
  end
end
