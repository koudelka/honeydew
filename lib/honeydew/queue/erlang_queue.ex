defmodule Honeydew.Queue.ErlangQueue do
  use Honeydew.Queue
  alias Honeydew.Job
  alias Honeydew.Queue.State

  def init(_queue_name, []) do
    # {pending, in_progress}
    {:ok, {:queue.new, Map.new}}
  end

  #
  # GenStage Callbacks
  #

  def handle_demand(demand, %State{outstanding: 0} = state) when demand > 0 do
    {state, jobs} = reserve(state, demand)

    {:noreply, jobs, %{state | outstanding: demand - Enum.count(jobs)}}
  end

  #
  # Enqueuing
  #

  def handle_call({:enqueue, job}, _from, %State{suspended: true} = state) do
    {state, job} = enqueue(state, job)
    {:reply, {:ok, job}, [], state}
  end

  # there's no demand outstanding, queue the task.
  def handle_call({:enqueue, job}, _from, %State{outstanding: 0} = state) do
    {state, job} = enqueue(state, job)
    {:reply, {:ok, job}, [], state}
  end

  # there's demand outstanding, enqueue the job and issue as many jobs as possible
  def handle_call({:enqueue, job}, _from, %State{outstanding: outstanding} = state) do
    {state, job} = enqueue(state, job)
    {state, jobs} = reserve(state, outstanding)

    {:reply, {:ok, job}, jobs, %{state | outstanding: outstanding - Enum.count(jobs)}}
  end

  #
  # Ack/Nack
  #

  def handle_cast({:ack, %Job{private: id}}, %State{private: {pending, in_progress}} = state) do
    {:noreply, [], %{state | private: {pending, Map.delete(in_progress, id)}}}
  end

  # requeue
  # def handle_cast({:nack, %Job{private: id} = job, true}, %State{private: {pending, in_progress}}) do
  #   #FIXME
  #   handle_cast({:enqueue, job}, %State{private: {pending, Map.delete(in_progress, id)}})
  # end

  # don't requeue
  def handle_cast({:nack, job, false}, state) do
    handle_cast({:ack, job}, state)
  end


  #
  # Suspend/Resume
  #

  def handle_cast(:suspend, state) do
    {:noreply, [], state}
  end

  def handle_cast(:resume, %State{outstanding: outstanding} = state) do
    {state, jobs} = reserve(state, outstanding)

    {:noreply, jobs, %{state | outstanding: outstanding - Enum.count(jobs)}}
  end


  #
  # Helpers
  #

  def status({pending, in_progress}) do
    %{count: :queue.len(pending) + map_size(in_progress),
      in_progress: map_size(in_progress)}
  end

  def filter({pending, in_progress}, function) do
    (function |> :queue.filter(pending) |> :queue.to_list) ++
      (in_progress |> Map.values |> Enum.filter(function))
  end

  def cancel({pending, in_progress}, %Job{private: private}) do
    filter = fn
      %Job{private: ^private} -> false;
      _ -> true
    end

    new_pending = :queue.filter(filter, pending)

    reply = cond do
      :queue.len(pending) > :queue.len(new_pending) -> :ok
      in_progress |> Map.values |> Enum.filter(&(!filter.(&1))) |> Enum.count > 0 -> {:error, :in_progress}
      true -> nil
    end

    {reply, {new_pending, in_progress}}
  end


  defp enqueue(%State{private: {pending, in_progress}} = state, job) do
    job = %{job | private: :erlang.unique_integer}
    {%{state | private: {:queue.in(job, pending), in_progress}}, job}
  end

  defp reserve(state, num), do: do_reserve([], state, num)

  defp do_reserve(jobs, state, 0), do: {state, jobs}

  defp do_reserve(jobs, %State{private: {pending, in_progress}} = state, num) do
    case :queue.out(pending) do
      {:empty, _pending} -> {state, jobs}
      {{:value, job}, pending} ->
        job = start_monitor(job, state)
        do_reserve([job | jobs], %{state | private: {pending, Map.put(in_progress, job.private, job)}}, num - 1)
    end
  end

end
