defmodule Honeydew.Queue.ErlangQueue do
  @moduledoc """
  An in-memory queue implementation.

  This is a simple FIFO queue implemented with the `:queue` and `Map` modules.
  """
  require Logger
  alias Honeydew.Job
  alias Honeydew.Queue

  @behaviour Queue

  @impl true
  def validate_args!([]), do: :ok
  def validate_args!(args), do: raise(ArgumentError, "You provided arguments (#{inspect args}) to the #{__MODULE__} queue, it's expecting an empty list, or just the bare module.")

  @impl true
  def init(_name, []) do
    # {pending, in_progress}
    {:ok, {:queue.new, Map.new}}
  end

  #
  # Enqueue/Reservee
  #

  @impl true
  def enqueue(job, {pending, in_progress}) do
    job = %{job | private: :erlang.unique_integer}
    {{:queue.in(job, pending), in_progress}, job}
  end

  @impl true
  def reserve({pending, in_progress} = state) do
    case :queue.out(pending) do
      {:empty, _pending} ->
        {:empty, state}
      {{:value, job}, pending} ->
        {job, {pending, Map.put(in_progress, job.private, job)}}
    end
  end

  #
  # Ack/Nack
  #

  @impl true
  def ack(%Job{private: id}, {pending, in_progress}) do
    {pending, Map.delete(in_progress, id)}
  end

  @impl true
  def nack(%Job{private: id} = job, {pending, in_progress}) do
    {:queue.in_r(job, pending), Map.delete(in_progress, id)}
  end

  #
  # Helpers
  #

  @impl true
  def status({pending, in_progress}) do
    %{count: :queue.len(pending) + map_size(in_progress),
      in_progress: map_size(in_progress)}
  end

  @impl true
  def filter({pending, in_progress}, function) do
    (function |> :queue.filter(pending) |> :queue.to_list) ++
      (in_progress |> Map.values |> Enum.filter(function))
  end

  @impl true
  def cancel(%Job{private: private}, {pending, in_progress}) do
    filter = fn
      %Job{private: ^private} -> false;
      _ -> true
    end

    new_pending = :queue.filter(filter, pending)

    reply = cond do
      :queue.len(pending) > :queue.len(new_pending) -> :ok
      in_progress |> Map.values |> Enum.filter(&(!filter.(&1))) |> Enum.count > 0 -> {:error, :in_progress}
      true -> {:error, :not_found}
    end

    {reply, {new_pending, in_progress}}
  end
end
