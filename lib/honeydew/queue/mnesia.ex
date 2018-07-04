defmodule Honeydew.Queue.Mnesia do
  @moduledoc """
  A mnesia-based queue implementation.

  This queue is configurable in all the ways mnesia is. For example, you can:

  * Run with replication (with queues running on multiple nodes)
  * Persist jobs to disk (dets)
  * Follow various safety modes ("access contexts")
  """
  require Honeydew.Job
  require Logger
  alias Honeydew.Job
  alias Honeydew.Queue

  @behaviour Honeydew.Queue

  # private queue state
  defmodule PState do
    @moduledoc false
    defstruct [:table, :access_context]
  end

  # TODO: document. :(
  @pending_match_spec [{Job.job(private: {false, :_}, _: :_) |> Job.to_record(:_), [], [:"$_"]}]


  @impl true
  def init(queue_name, [nodes, table_opts, opts]) do
    access_context = Keyword.get(opts, :access_context, :sync_transaction)

    case :mnesia.create_schema(nodes) do
      :ok -> :ok
      {:error, {_, {:already_exists, _}}} -> :ok
    end

    # assert that mnesia started correctly everywhere?
    :rpc.multicall(nodes, :mnesia, :start, [])

    table_def =
      table_opts
      |> Keyword.put(:type, :ordered_set)
      |> Keyword.put(:attributes, Job.fields)

    # inspect/1 here becase queue_name can be of the form {:global, poolname}
    table = ["honeydew", inspect(queue_name)] |> Enum.join("_") |> String.to_atom

    case :mnesia.create_table(table, table_def) do
      {:atomic, :ok} -> :ok
      {:aborted, {:already_exists, ^table}} -> :ok
    end

    :ok = :mnesia.wait_for_tables([table], 15_000)

    :ok = reset_after_crash(table, access_context)

    {:ok, %PState{table: table, access_context: access_context}}
  end

  #
  # Enqueue/Reserve
  #

  @impl true
  def enqueue(job, %PState{table: table, access_context: access_context} = state) do
    job = %{job | private: {false, :erlang.unique_integer([:monotonic])}} # {in_progress, :id}

    :mnesia.activity(access_context, fn ->
      :ok =
        job
        |> Job.to_record(table)
        |> :mnesia.write
    end)

    {state, job}
  end

  # should the recursion be outside of the transaction?
  @impl true
  def reserve(%PState{table: table, access_context: access_context} = state) do
    :mnesia.activity(access_context, fn ->
      case :mnesia.select(table, @pending_match_spec, 1, :read) do
        :"$end_of_table" -> {:empty, state}
        {[job], _cont} ->
          {_, id} = Job.job(job, :private)

          :ok = :mnesia.delete_object(job)

          job = Job.job(job, private: {node(), id})

          :ok = :mnesia.write(job)

          {Job.from_record(job), state}
      end
    end)
  end

  #
  # Ack/Nack
  #

  @impl true
  def ack(%Job{private: private}, %PState{table: table} = state) do
    :ok = :mnesia.dirty_delete(table, private)

    state
  end

  @impl true
  def nack(%Job{private: {_, id}, failure_private: failure_private} = job, %PState{table: table, access_context: access_context} = state) do
    :mnesia.activity(access_context, fn ->
      :ok =
        %{job | private: {false, id}, failure_private: failure_private}
        |> Job.to_record(table)
        |> :mnesia.write

      :ok = :mnesia.delete({table, {node(), id}})
    end)

    state
  end

  #
  # Helpers
  #

  # foldl might be too heavy...
  @impl true
  def status(%PState{table: table}) do
    {pending, in_progress} =
      :mnesia.activity(:async_dirty, fn ->
        :mnesia.foldl(fn job, {pending, in_progress} ->
          job
          |> Job.to_record
          |> case do
               Job.job(private: {false, _}) ->
                 {pending + 1, in_progress}
               Job.job(private: {_node, _}) ->
                 {pending, in_progress + 1}
             end
        end, {0, 0}, table)
      end)

    %{
      mnesia: :mnesia.table_info(table, :all),
      count: pending + in_progress,
      in_progress: in_progress
    }
  end

  @impl true
  def filter(%PState{table: table, access_context: access_context}, map) when is_map(map) do
    :mnesia.activity(access_context, fn ->
      map
      |> Job.match_spec(table)
      |> :mnesia.match_object
      |> Enum.map(&Job.from_record/1)
    end)
  end

  @impl true
  def filter(%PState{table: table, access_context: access_context}, function) do
    :mnesia.activity(access_context, fn ->
      :mnesia.foldl(fn job, list ->
        job
        |> Job.from_record
        |> function.()
        |> case do
             true -> [job | list]
             false -> list
           end
      end, [], table)
      |> Enum.map(&Job.from_record/1)
    end)
  end

  @impl true
  @spec cancel(Job.t, Queue.private) :: {:ok | {:error, :in_progress | :not_found}, Queue.private}
  def cancel(%Job{private: {_, id}, }, %PState{table: table, access_context: access_context} = state) do
    reply =
      :mnesia.activity(access_context, fn ->
        Job.job(private: {:_, id}, _: :_)
        |> Job.to_record(table)
        |> :mnesia.match_object
        |> Enum.map(&Job.to_record/1)
        |> case do
             [] -> {:error, :not_found}
             [Job.job(private: {false, id})] ->
               :ok = :mnesia.delete({table, {false, id}})
             [Job.job(private: {_node, _id})] ->
               {:error, :in_progress}
           end
      end)

    {reply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warn "[Honeydew] Queue #{inspect self()} received unexpected message #{inspect msg}"
    {:noreply, state}
  end

  defp reset_after_crash(table, access_context) do
    :mnesia.activity(access_context, fn ->
      table
      |> :mnesia.select(in_progress_match_spec(), :read)
      |> Enum.each(fn job ->
        {_, id} = Job.job(job, :private)

        :ok = :mnesia.delete_object(job)

        job = Job.job(job, private: {false, id})

        :ok = :mnesia.write(job)
      end)
    end)
  end

  defp in_progress_match_spec do
    [{Job.job(private: {node(), :_}, _: :_) |> Job.to_record(:_), [], [:"$_"]}]
  end
end
