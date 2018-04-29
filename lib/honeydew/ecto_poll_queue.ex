defmodule Honeydew.EctoPollQueue do
  alias Honeydew.PollQueue
  alias Honeydew.EctoSource

  @type queue_name :: Honeydew.queue_name()

  @type ecto_poll_queue_spec_opt ::
    Honeydew.queue_spec_opt |
    {:schema, module} |
    {:repo, module} |
    {:poll_interval, pos_integer} |
    {:stale_timeout, pos_integer}

  @doc """
  Creates a supervision spec for an Ecto Poll Queue.

  In addition to the arguments from `queue_spec/4`:

  You *must* provide:

  - `repo`: is your Ecto.Repo module
  - `schema`: is your Ecto.Schema module

  You may provide:

  - `poll_interval`: is how often Honeydew will poll your database when the queue is silent, in seconds (default: 10)
  - `stale_timeout`: is the amount of time a job can take before it risks retry, in seconds (default: 300)

  For example:

  - `Honeydew.queue_spec(:classify_photos, repo: MyApp.Repo, schema: MyApp.Photo)`

  - `Honeydew.queue_spec(:classify_photos, repo: MyApp.Repo, schema: MyApp.Photo failure_mode: {Honeydew.Retry, times: 3})`
  """
  @spec child_spec([queue_name | ecto_poll_queue_spec_opt]) :: Supervisor.Spec.spec
  def child_spec([queue_name | opts]) do
    {poll_interval, opts} = Keyword.pop(opts, :poll_interval)
    {stale_timeout, opts} = Keyword.pop(opts, :stale_timeout)
    {database_override, opts} = Keyword.pop(opts, :database)

    if opts[:queue] do
      raise ArgumentError, cant_specify_queue_type_error(opts[:queue])
    end

    schema = Keyword.fetch!(opts, :schema)
    repo = Keyword.fetch!(opts, :repo)
    sql = EctoSource.SQL.module(repo, database_override)

    ecto_source_args =
      [schema: schema,
       repo: repo,
       sql: sql,
       poll_interval: poll_interval || 10,
       stale_timeout: stale_timeout || 300]

    opts =
      opts
      |> Keyword.delete(:schema)
      |> Keyword.delete(:repo)
      |> Keyword.put(:queue, {PollQueue, [EctoSource, ecto_source_args]})

    Honeydew.queue_spec(queue_name, opts)
  end

  @doc false
  def cant_specify_queue_type_error(argument) do
    "you can't provide the :queue argument for Ecto Poll Queues, it's already a `PollQueue` with the `EctoSource`. You gave #{inspect argument}"
  end

  defmodule Schema do
    defmacro honeydew_fields(queue) do
      quote do
        alias Honeydew.EctoSource.ErlangTerm

        unquote(queue)
        |> Honeydew.EctoSource.field_name(:lock)
        |> Ecto.Schema.field(:integer)

        unquote(queue)
        |> Honeydew.EctoSource.field_name(:private)
        |> Ecto.Schema.field(ErlangTerm)
      end
    end
  end

  defmodule Migration do
    defmacro honeydew_fields(queue, opts \\ []) do
      quote do
        require unquote(__MODULE__)
        alias Honeydew.EctoSource.SQL
        alias Honeydew.EctoSource.ErlangTerm
        require SQL

        database = Keyword.get(unquote(opts), :database, nil)

        sql_module =
          :repo
          |> Ecto.Migration.Runner.repo_config(nil)
          |> SQL.module(database)

        unquote(queue)
        |> Honeydew.EctoSource.field_name(:lock)
        |> Ecto.Migration.add(sql_module.integer_type(), default: SQL.ready_fragment(sql_module))

        unquote(queue)
        |> Honeydew.EctoSource.field_name(:private)
        |> Ecto.Migration.add(ErlangTerm.type())
      end
    end

    defmacro honeydew_indexes(table, queue, opts \\ []) do
      quote do
        lock_field = unquote(queue) |> Honeydew.EctoSource.field_name(:lock)
        Ecto.Migration.create(index(unquote(table), [lock_field], unquote(opts)))
      end
    end
  end

end
