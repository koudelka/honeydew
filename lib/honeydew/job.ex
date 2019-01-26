defmodule Honeydew.Job do
  @moduledoc """
  A Honeydew job.
  """

  require Record

  @type private :: term()

  # :private needs to be first, the mnesia queue's ordering depends on it
  @fields [:private, # queue's private state
           :failure_private, # failure mode's private state
           :task,
           :from, # if the requester wants the result, here's where to send it
           :result,
           :by, # node last processed the job
           :queue,
           :job_monitor,
           :enqueued_at,
           :started_at,
           :completed_at]

  @kv Enum.map(@fields, &{&1, nil})

  defstruct @kv
  @doc false
  Record.defrecord :job, @kv
  @match_spec @fields |> Enum.map(&{&1, :_}) |> Enum.into(%{})

  @type t :: %__MODULE__{
    task: Honeydew.task | nil,
    queue: Honeydew.queue_name,
    private: private
  }

  @doc false
  def fields, do: @fields

  vars = @fields |> Enum.map(&Macro.var(&1, __MODULE__))
  vars_keyword_list = Enum.zip(@fields, vars)

  @doc false
  def new(task, queue) do
    %__MODULE__{task: task, queue: queue, enqueued_at: System.system_time(:millisecond)}
  end

  @doc false
  def to_record(%{unquote_splicing(vars_keyword_list)}, name) do
    {name, unquote_splicing(vars)}
  end

  @doc false
  def to_record({_name, unquote_splicing(vars)}, name) do
    {name, unquote_splicing(vars)}
  end

  @doc false
  def to_record({_name, unquote_splicing(vars)}) do
    {:job, unquote_splicing(vars)}
  end

  @doc false
  def from_record({_name, unquote_splicing(vars)}) do
    %__MODULE__{unquote_splicing(vars_keyword_list)}
  end

  @doc false
  def match_spec(map, name) do
    @match_spec
    |> Map.merge(map)
    |> Honeydew.Job.to_record(name)
  end
end
