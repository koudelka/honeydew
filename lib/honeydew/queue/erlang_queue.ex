defmodule Honeydew.Queue.ErlangQueue do
  use Honeydew.Queue
  alias Honeydew.Job
  alias Honeydew.Queue.State

  def init(_queue_name, []) do
    # {pending, in_progress}
    {:ok, {:queue.new, Map.new}}
  end

  #
  # Enqueue/Reservee
  #

  def enqueue(job, %State{private: {pending, in_progress}} = state) do
    job = %{job | private: :erlang.unique_integer}
    {%{state | private: {:queue.in(job, pending), in_progress}}, job}
  end

  def reserve(%State{private: {pending, in_progress}} = state) do
    case :queue.out(pending) do
      {:empty, _pending} ->
        nil
      {{:value, job}, pending} ->
        {%{state | private: {pending, Map.put(in_progress, job.private, job)}}, job}
    end
  end

  #
  # Ack/Nack
  #

  def ack(%Job{private: id}, %State{private: {pending, in_progress}} = state) do
    %{state | private: {pending, Map.delete(in_progress, id)}}
  end

  def nack(%Job{private: id} = job, %State{private: {pending, in_progress}} = state) do
    %{state | private: {:queue.in_r(job, pending), Map.delete(in_progress, id)}}
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

  def cancel(%Job{private: private}, {pending, in_progress}) do
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
end
