defmodule Honeydew.EctoSource.SQL do
  alias Honeydew.EctoSource.State

  #
  # you might be wondering "what's all this shitty sql for?", it's to make sure that the database is sole arbiter of "now",
  # in case of clock skew between the various nodes running this queue
  #

  @type sql_fragment :: String.t()

  @spec time_in_msecs_sql(sql_fragment) :: sql_fragment
  def time_in_msecs_sql(time) do
    "CAST(EXTRACT(epoch from (#{time})) * 1000 AS INT)"
  end

  @spec now_msecs_sql() :: sql_fragment
  def now_msecs_sql do
    time_in_msecs_sql("NOW()")
  end

  @spec msecs_ago_sql(sql_fragment | State.stale_timeout()) :: sql_fragment
  def msecs_ago_sql(msecs) do
    "#{now_msecs_sql()} - #{msecs}"
  end

  defmacro msecs_ago_fragment(msecs) do
    sql = msecs_ago_sql("?")

    quote do
      fragment(unquote(sql), unquote(msecs))
    end
  end

  # "I left in love, in laughter, and in truth. And wherever truth, love and laughter abide, I am there in spirit."
  @spec far_in_the_past() :: NaiveDateTime.t()
  def far_in_the_past do
    ~N[1994-03-26 04:20:00]
  end

  defmacro ready_fragment do
    sql =
      "CAST('#{far_in_the_past()}' AS TIMESTAMP)"
      |> time_in_msecs_sql
      |> msecs_ago_sql

    quote do
      fragment(unquote(sql))
    end
  end

  @spec reserve_sql(State.t()) :: String.t()
  def reserve_sql(state) do
    "UPDATE #{state.table}
    SET #{state.lock_field} = #{now_msecs_sql()}
    WHERE #{state.lock_field} BETWEEN 0 AND #{msecs_ago_sql(state.stale_timeout)}
    ORDER BY #{state.lock_field}, #{state.key_field}
    LIMIT 1
    RETURNING #{state.key_field}, #{state.private_field}"
  end

  @spec cancel_sql(State.t()) :: String.t()
  def cancel_sql(state) do
    "UPDATE #{state.table}
    SET #{state.lock_field} = NULL
    WHERE
      id = $1
      AND #{state.lock_field} BETWEEN 0 AND #{msecs_ago_sql(state.stale_timeout)}
    LIMIT 1
    RETURNING #{state.lock_field}"
  end
end
