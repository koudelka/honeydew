if Code.ensure_loaded?(Ecto) do

  defmodule Honeydew.EctoSource.SQL.Postgres do
    alias Honeydew.EctoSource
    alias Honeydew.EctoSource.SQL

    @behaviour SQL

    @impl true
    def integer_type do
      :bigint
    end

    @impl true
    def ready do
      SQL.far_in_the_past()
      |> time_in_msecs
      |> msecs_ago
    end

    @impl true
    def reserve(state) do
      "UPDATE #{state.table}
      SET #{state.lock_field} = #{now_msecs()}
      WHERE id = (
        SELECT id
        FROM #{state.table}
        WHERE #{state.lock_field} BETWEEN 0 AND #{msecs_ago(state.stale_timeout)}
        ORDER BY #{state.lock_field}, #{state.key_field}
        LIMIT 1
        FOR UPDATE SKIP LOCKED
      )
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
      "SELECT COUNT(CASE WHEN #{state.lock_field} IS NOT NULL THEN 1 ELSE NULL END) AS count,
              COUNT(CASE WHEN #{state.lock_field} >= #{msecs_ago(state.stale_timeout)} THEN 1 ELSE NULL END) AS in_progress,
              COUNT(CASE WHEN #{state.lock_field} = #{EctoSource.abandoned()} THEN 1 ELSE NULL END) AS abandoned
      FROM #{state.table}"
    end

    defp msecs_ago(msecs) do
      "#{now_msecs()} - #{msecs}"
    end

    defp now_msecs do
      "(CAST(EXTRACT(epoch FROM NOW()) * 1000 AS BIGINT))"
    end

    defp time_in_msecs(time) do
      "(CAST(EXTRACT(epoch from timestamp '#{time}') * 1000 AS BIGINT))"
    end

  end

end
