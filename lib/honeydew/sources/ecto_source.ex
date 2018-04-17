#
# The goal of this module is to lamprey a queue onto an existing ecto schema with as few requirements and as little
# disruption as possible. It adds two fields to the schema, a "lock" field and a "private" field. As we don't know
# which database we're running on, I've tried to keep it vanilla, no special db features are used.
#
# In order to use the queue, the user has to do just a few extra things, outside of setting up the honeydew queue as normal:
#  1. Add fields to the schema, with `honeydew_fields/1`
#  2. Add columns to the database with `honeydew_migration_fields/1`
#  3. Add indexes to the database with `honeydew_migration_indexes/1`
#
#
# The lock field is an integer overloaded with three jobs:
#  1. Acts as a lock, to ensure that only one worker is proessing the job at a time, no matter how many nodes are running
#     copies of the queue. It expires after a configurable period of time (the queue process or entire node crashed).
#  2. Indicates the status of the job, it can be either:
#     - "ready", between zero and the beginning of the stale window
#     - "in progress", inside of the stale window
#     - "abandoned", -1
#  3. Indicate the order in which jobs should be processed.
#
#
#
#      unix epoch zero
#             |<--------------------- ready --------------------------->|
#             v                                                         |
# time <------0---------------|----------------------------|------------|-------|--->
#            ^                ^                            ^            ^       ^
#       abandoned(-1)      new jobs                 far_in_the_past    stale   now
#                     (now - far_in_the_past)
#
#
#
# The private field is a simple binary field that contains an erlang term, it's used for data that needs to be
# persisteed between job attempts, specificaly, it's the "failure_private" contents of the job.
#
#
# As the main objective is to minimize disruption, I wanted the default values for the additional fields to be set
# statically in the migration, rather than possibly interfering with the user's schema validations on save etc...
# The only runtimes configuration the user should set is the `stale_timeout`, which should be the maximum expected
# time that a job will take.
#
#

#
# This module is tested and dialyzed via the included test project in examples/ecto_poll_queue
#
if Code.ensure_loaded?(Ecto) do

  defmodule Honeydew.EctoSource do
    require Logger
    alias Honeydew.Job
    alias Honeydew.PollQueue
    alias Honeydew.EctoSource.State
    alias Honeydew.EctoSource.ErlangTerm
    import Honeydew.EctoSource.SQL

    @behaviour PollQueue

    defmacro __using__(_env) do
      quote do
        import unquote(__MODULE__),
          only: [honeydew_fields: 1,
                 honeydew_migration_fields: 1,
                 honeydew_migration_indexes: 2,
                 honeydew_migration_indexes: 3]
      end
    end

    defmacro honeydew_fields(queue) do
      quote do
        unquote(queue)
        |> unquote(__MODULE__).field_name(:lock)
        |> Ecto.Schema.field(:integer)

        unquote(queue)
        |> unquote(__MODULE__).field_name(:private)
        |> Ecto.Schema.field(unquote(ErlangTerm))
      end
    end

    defmacro honeydew_migration_fields(queue) do
      quote do
        require unquote(__MODULE__)
        alias Honeydew.EctoSource.SQL
        require SQL

        unquote(queue)
        |> unquote(__MODULE__).field_name(:lock)
        |> Ecto.Migration.add(:integer, default: SQL.ready_fragment())

        unquote(queue)
        |> unquote(__MODULE__).field_name(:private)
        |> Ecto.Migration.add(unquote(ErlangTerm).type())
      end
    end

    defmacro honeydew_migration_indexes(table, queue, opts \\ []) do
      quote do
        lock_field = unquote(queue) |> unquote(__MODULE__).field_name(:lock)
        Ecto.Migration.create(index(unquote(table), [lock_field], unquote(opts)))
      end
    end

    @abandoned -1
    def abandoned, do: @abandoned

    @impl true
    def init(queue, args) do
      schema = Keyword.fetch!(args, :schema)
      repo = Keyword.fetch!(args, :repo)
      stale_timeout = Keyword.get(args, :stale_timeout, 5 * 60) * 1_000 # default to five minutes

      table = schema.__schema__(:source)
      key_field = schema.__schema__(:primary_key) |> List.first()

      {:ok, %State{schema: schema,
                   table: table,
                   key_field: key_field,
                   lock_field: field_name(queue, :lock),
                   private_field: field_name(queue, :private),
                   repo: repo,
                   queue: queue,
                   stale_timeout: stale_timeout}}
    end

    # lock a row for processing
    @impl true
    def reserve(%State{queue: queue, schema: schema, repo: repo, key_field: key_field, private_field: private_field} = state) do
      state
      |> reserve_sql
      |> repo.query([])
      |> case do
        {:ok, %{num_rows: 1, rows: [[id, private]]}} ->
          # convert key and private_field from db representation to schema's type
          %^schema{^key_field => id, ^private_field => private} =
            repo.load(schema, %{key_field => id, private_field => private})

          job =
            id
            |> schema.honeydew_task(queue)
            |> Job.new(queue)
            |> struct(failure_private: private)

          {{:value, {id, job}}, state}

        {:ok, %{num_rows: 0}} ->
          {:empty, state}
      end
    end

    @impl true
    # acked without completing, either moved or abandoned
    def ack(%Job{private: id, completed_at: nil}, state) do
      finalize(id, @abandoned, nil, state)
    end

    @impl true
    def ack(%Job{private: id}, state) do
      finalize(id, nil, nil, state)
    end

    @impl true
    def nack(%Job{private: id, failure_private: private}, state) do
      finalize(id, 1, private, state)
    end

    @impl true
    def cancel(%Job{private: id}, %State{schema: schema, repo: repo, key_field: key_field} = state) do
      {:ok, id} = dump_field(schema, repo, key_field, id)

      state
      |> cancel_sql
      |> repo.query([id])
      |> case do
           {:ok, %{num_rows: 1}} ->
             {:ok, state}
           {:ok, %{num_rows: 0}} ->
             {{:error, :not_found}, state}
         end
    end

    @impl true
    def status(%State{schema: schema, repo: repo, key_field: key_field, lock_field: lock_field, stale_timeout: stale_timeout}) do
      import Ecto.Query

      count_query =
        from(s in schema,
          select: count(field(s, ^key_field)),
          where: not is_nil(field(s, ^lock_field)))

      in_progress_query =
        from(s in count_query, where: field(s, ^lock_field) > msecs_ago_fragment(^stale_timeout))

      abandoned_query =
        from(s in schema,
          select: count(field(s, ^key_field)),
          where: field(s, ^lock_field) == ^@abandoned)

      [count] = repo.all(count_query)
      [in_progress] = repo.all(in_progress_query)
      [abandoned] = repo.all(abandoned_query)

      %{count: count, in_progress: in_progress, abandoned: abandoned}
    end

    @impl true
    def handle_info(msg, queue_state) do
      Logger.warn("[Honeydew] Queue #{inspect(self())} received unexpected message #{inspect(msg)}")

      {:noreply, queue_state}
    end

    def field_name(queue, name) do
      :"honeydew_#{Honeydew.table_name(queue)}_#{name}"
    end

    defp finalize(id, lock, private, state) do
      import Ecto.Query

      from(s in state.schema,
        where: field(s, ^state.key_field) == ^id,
        update: [set: ^[{state.lock_field, lock}, {state.private_field, private}]])
      |> state.repo.update_all([]) # avoids touching auto-generated fields

      state
    end

    defp dump_field(schema, repo, field, value) do
      type = schema.__schema__(:type, field)
      Ecto.Type.adapter_dump(repo.__adapter__(), type, value)
    end

  end
end
