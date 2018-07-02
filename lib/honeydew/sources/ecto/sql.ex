defmodule Honeydew.EctoSource.SQL do
  alias Honeydew.EctoSource.State
  alias Honeydew.EctoSource.SQL.Cockroach
  alias Honeydew.EctoSource.SQL.Postgres

  #
  # you might be wondering "what's all this shitty sql for?", it's to make sure that the database is sole arbiter of "now",
  # in case of clock skew between the various nodes running this queue
  #

  @type sql :: String.t()
  @type msecs :: integer()
  @type repo :: module()
  @type override :: :cockroachdb | nil
  @type sql_module :: Postgres | Cockroach
  @type filter :: atom

  @callback integer_type :: atom()
  @callback reserve(State.t()) :: sql
  @callback cancel(State.t()) :: sql
  @callback ready :: sql
  @callback status(State.t()) :: sql
  @callback filter(State.t(), filter) :: sql

  @spec module(repo, override) :: sql_module | no_return
  def module(repo, override) do
    case override do
      :cockroachdb ->
        Cockroach

      nil ->
        case repo.__adapter__() do
          Ecto.Adapters.Postgres ->
            Postgres
          unsupported ->
            raise ArgumentError, unsupported_adapter_error(unsupported)
        end
    end
  end

  defmacro ready_fragment(module) do
    quote do
      unquote(module).ready
      |> fragment
    end
  end

  @doc false
  defp unsupported_adapter_error(adapter) do
    "your repo's ecto adapter, #{inspect adapter}, isn't currently supported, but it's probably not hard to implement, open an issue and we'll chat!"
  end

  # "I left in love, in laughter, and in truth. And wherever truth, love and laughter abide, I am there in spirit."
  @spec far_in_the_past() :: NaiveDateTime.t()
  def far_in_the_past do
    ~N[1994-03-26 04:20:00]
  end

end
