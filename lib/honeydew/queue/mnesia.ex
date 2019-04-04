defmodule Honeydew.Queue.Mnesia do
  @moduledoc """
  A mnesia-based queue implementation.

  This queue is configurable in all the ways mnesia is. For example, you can:

  * Run with replication (with queues running on multiple nodes)
  * Persist jobs to disk (dets)
  """
  require Honeydew.Job
  require Logger
  require Record

  alias Honeydew.Job
  alias Honeydew.Queue
  alias Honeydew.Queue.State, as: QueueState
  alias __MODULE__.WrappedJob

  @behaviour Queue

  # private queue state
  defmodule PState do
    @moduledoc false

    defstruct [:table,
               :in_progress_table,
               :access_context]
  end

  @poll_interval 1_000

  @impl true
  def validate_args!(opts) do
    nodes_list = nodes_list(opts)

    if Enum.empty?(nodes_list) do
      raise ArgumentError, "You must provide either :ram_copies, :disc_copies or :disc_only_copies as to #{__MODULE__}, for instance `[disc_copies: [node()]]`."
    end

    Enum.each(nodes_list, fn
      node when not is_atom(node) ->
        raise ArgumentError, "You provided node name `#{inspect node}` to the #{__MODULE__} queue, node names must be atoms."
      _ -> :ok
    end)

    :ok
  end

  @impl true
  def init(queue_name, opts) do
    nodes = nodes_list(opts)

    if on_disk?(opts) do
      case :mnesia.create_schema(nodes) do
        :ok -> :ok
        {:error, {_, {:already_exists, _}}} -> :ok
      end
    end

    # assert that mnesia started correctly everywhere?
    :rpc.multicall(nodes, :mnesia, :start, [])

    generic_table_def = [attributes: WrappedJob.record_fields(),
                         record_name: WrappedJob.record_name()]

    # inspect/1 here becase queue_name can be of the form {:global, poolname}
    table = ["honeydew", inspect(queue_name)] |> Enum.join("_") |> String.to_atom
    in_progress_table = ["honeydew", inspect(queue_name), "in_progress"] |> Enum.join("_") |> String.to_atom

    tables = %{table => [type: :ordered_set],
               in_progress_table => [type: :set]}

    Enum.each(tables, fn {name, opts} ->
      table_definition = Keyword.merge(generic_table_def, opts)

      case :mnesia.create_table(name, table_definition) do
        {:atomic, :ok} ->
          :ok

        {:aborted, {:already_exists, ^name}} ->
          :ok
      end
    end)

    :ok =
      tables
      |> Map.keys()
      |> :mnesia.wait_for_tables(15_000)

    state = %PState{table: table,
                    in_progress_table: in_progress_table,
                    access_context: access_context(opts)}

    :ok = reset_after_crash(state)

    poll()

    {:ok, state}
  end

  #
  # Enqueue/Reserve
  #

  @impl true
  def enqueue(job, %PState{table: table} = state) do
    wrapped_job = WrappedJob.new(job)
    wrapped_job_record = WrappedJob.to_record(wrapped_job)

    :ok = :mnesia.dirty_write(table, wrapped_job_record)

    {state, wrapped_job.job}
  end

  @impl true
  def reserve(%PState{table: table, access_context: access_context} = state) do
    :mnesia.activity(access_context, fn ->
      table
      |> :mnesia.select(WrappedJob.reserve_match_spec(), 1, :read)
      |> case do
           :"$end_of_table" ->
             {:empty, state}

           {[wrapped_job_record], _cont} ->
             :ok = move_to_in_progress_table(wrapped_job_record, state)
             %WrappedJob{job: job} = WrappedJob.from_record(wrapped_job_record)
             {job, state}
         end
    end)
  end

  #
  # Ack/Nack
  #

  @impl true
  def ack(%Job{private: id}, %PState{in_progress_table: in_progress_table, access_context: access_context} = state) do
    pattern = WrappedJob.id_pattern(id)

    :mnesia.activity(access_context, fn ->
      [wrapped_job] = :mnesia.match_object(in_progress_table, pattern, :read)
      :ok = :mnesia.delete_object(in_progress_table, wrapped_job, :write)
    end)

    state
  end

  @impl true
  def nack(%Job{private: id, failure_private: failure_private, delay_secs: delay_secs}, %PState{} = state) do
    move_to_pending_table(id, %{failure_private: failure_private, delay_secs: delay_secs}, state)

    state
  end

  #
  # Helpers
  #

  @impl true
  def status(%PState{table: table, in_progress_table: in_progress_table}) do
    mnesia_info = %{
      table => :mnesia.table_info(table, :all),
      in_progress_table => :mnesia.table_info(in_progress_table, :all)
    }

    num_pending = mnesia_info[table][:size]
    num_in_progress = mnesia_info[in_progress_table][:size]

    %{
      mnesia: mnesia_info,
      count: num_pending + num_in_progress,
      in_progress: num_in_progress
    }
  end

  @impl true
  def filter(%PState{table: table, access_context: access_context}, map) when is_map(map) do
    :mnesia.activity(access_context, fn ->
      pattern = WrappedJob.filter_pattern(map)

      table
      |> :mnesia.match_object(pattern, :read)
      |> Enum.map(&WrappedJob.from_record/1)
      |> Enum.map(fn %WrappedJob{job: job} -> job end)
    end)
  end

  @impl true
  def filter(%PState{table: table, access_context: access_context}, function) do
    :mnesia.activity(access_context, fn ->
      :mnesia.foldl(fn wrapped_job_record, list ->
        %WrappedJob{job: job} = WrappedJob.from_record(wrapped_job_record)

        job
        |> function.()
        |> case do
             true -> [job | list]
             false -> list
           end
      end, [], table)
    end)
  end

  @impl true
  @spec cancel(Job.t, Queue.private) :: {:ok | {:error, :in_progress | :not_found}, Queue.private}
  def cancel(%Job{private: id}, %PState{table: table, in_progress_table: in_progress_table, access_context: access_context} = state) do
    reply =
      :mnesia.activity(access_context, fn ->
        pattern = WrappedJob.id_pattern(id)

        table
        |> :mnesia.match_object(pattern, :read)
        |> case do
             [wrapped_job] ->
               :ok = :mnesia.delete_object(table, wrapped_job, :write)

             [] ->
               in_progress_table
               |> :mnesia.match_object(pattern, :read)
               |> case do
                    [] ->
                      {:error, :not_found}
                    [_wrapped_job] ->
                      {:error, :in_progress}
                  end
           end
      end)

    {reply, state}
  end

  defp reset_after_crash(%PState{in_progress_table: in_progress_table} = state) do
    in_progress_table
    |> :mnesia.dirty_first()
    |> case do
         :"$end_of_table" ->
           :ok

         key ->
           key
           |> WrappedJob.id_from_key
           |> move_to_pending_table(%{}, state)

           reset_after_crash(state)
       end
    :ok
  end

  defp move_to_in_progress_table(wrapped_job_record, %PState{table: table, in_progress_table: in_progress_table, access_context: access_context}) do
    :mnesia.activity(access_context, fn ->
      :ok = :mnesia.write(in_progress_table, wrapped_job_record, :write)
      :ok = :mnesia.delete({table, WrappedJob.key(wrapped_job_record)})
    end)
  end

  defp move_to_pending_table(id, updates, %PState{table: table, in_progress_table: in_progress_table, access_context: access_context}) do
    pattern = WrappedJob.id_pattern(id)

    :mnesia.activity(access_context, fn ->
      wrapped_job_record =
        in_progress_table
        |> :mnesia.match_object(pattern, :read)
        |> List.first

      %WrappedJob{job: job} = WrappedJob.from_record(wrapped_job_record)

      updated_wrapped_job_record =
        job
        |> struct(updates)
        |> WrappedJob.new
        |> WrappedJob.to_record

      :ok = :mnesia.write(table, updated_wrapped_job_record, :write)
      :ok = :mnesia.delete_object(in_progress_table, wrapped_job_record, :write)
    end)
  end

  defp access_context(opts) do
    if nodes_list(opts) == [node()] do
      if on_disk?(opts) do
        :async_dirty
      else
        :ets
      end
    else
      :sync_transaction
    end
  end

  defp nodes(opts) do
    ram_copies = Keyword.get(opts, :ram_copies, [])
    disc_copies = Keyword.get(opts, :disc_copies, [])
    disc_only_copies = Keyword.get(opts, :disc_only_copies, [])

    %{
      ram: ram_copies,
      disc: disc_copies,
      disc_only: disc_only_copies
    }
  end

  defp nodes_list(opts) do
    opts
    |> nodes
    |> Map.values
    |> List.flatten
  end

  defp on_disk?(opts) do
    nodes = nodes(opts)

    !Enum.empty?(nodes[:disc]) || !Enum.empty?(nodes[:disc_only])
  end

  @impl true
  def handle_info(:__poll__, %QueueState{} = queue_state) do
    poll()
    {:noreply, Queue.dispatch(queue_state)}
  end

  defp poll do
    {:ok, _} = :timer.send_after(@poll_interval, :__poll__)
  end
end
