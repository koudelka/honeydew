defmodule Honeydew.Queue.Mnesia do
  use Honeydew.Queue
  require Honeydew.Job
  alias Honeydew.Job
  alias Honeydew.Queue.State

  # private queue state
  defmodule PState do
    defstruct [:table, :access_context]
  end

  # TODO: document. :(
  @pending_match_spec [{Job.job(private: {false, :_}, _: :_) |> Job.to_record(:_), [], [:"$_"]}]


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
    {:ok, %PState{table: table, access_context: access_context}}
  end

  #
  # Enqueue/Reserve
  #

  def enqueue(%State{private: %PState{table: table, access_context: access_context}} = state, job) do
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
  def reserve(%State{private: %PState{table: table, access_context: access_context}} = state) do
    :mnesia.activity(access_context, fn ->
      case :mnesia.select(table, @pending_match_spec, 1, :read) do
        :"$end_of_table" -> nil
        {[job], _cont} ->
          {_, id} = Job.job(job, :private)

          :ok = :mnesia.delete_object(job)

          job = Job.job(job, private: {true, id})

          :ok = :mnesia.write(job)

          {state, Job.from_record(job)}
      end
    end)
  end

  #
  # Ack/Nack
  #

  def ack(%State{private: %PState{table: table}} = state, %Job{private: private}) do
    :ok = :mnesia.dirty_delete(table, private)

    state
  end

  def nack(%State{private: %PState{table: table, access_context: access_context}} = state, %Job{private: {_, id},
                                                                                                failure_private: failure_private} = job) do
    :mnesia.activity(access_context, fn ->
      :ok = :mnesia.delete({table, {true, id}})

      :ok =
        %{job | private: {false, id}, failure_private: failure_private}
        |> Job.to_record(table)
        |> :mnesia.write
    end)

    state
  end

  #
  # Helpers
  #

  # foldl might be too heavy...
  def status(%PState{table: table}) do
    {pending, in_progress} =
      :mnesia.activity(:async_dirty, fn ->
        :mnesia.foldl(fn job, {pending, in_progress} ->
          job
          |> Job.to_record
          |> case do
               Job.job(private: {false, _}) ->
                 {pending + 1, in_progress}
               Job.job(private: {true, _}) ->
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

  def filter(%PState{table: table, access_context: access_context}, map) when is_map(map) do
    :mnesia.activity(access_context, fn ->
      map
      |> Job.match_spec(table)
      |> :mnesia.match_object
      |> Enum.map(&Job.from_record/1)
    end)
  end

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

  def cancel(%PState{table: table, access_context: access_context} = queue, %Job{private: {_, id}}) do
    reply =
      :mnesia.activity(access_context, fn ->
        Job.job(private: {:_, id}, _: :_)
        |> Job.to_record(table)
        |> :mnesia.match_object
        |> Enum.map(&Job.to_record/1)
        |> case do
             [] -> nil
             [Job.job(private: {false, id})] ->
               :ok = :mnesia.delete({table, {false, id}})
             [Job.job(private: {true, _id})] ->
               {:error, :in_progress}
           end
      end)

    {reply, queue}
  end
end
