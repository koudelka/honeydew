defmodule Honeydew.Job do
  @moduledoc """
  A Honeydew job.
  """

  @type private :: term()

  defstruct [:private, # queue's private state
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

  @type t :: %__MODULE__{
    task: Honeydew.task | nil,
    queue: Honeydew.queue_name,
    private: private
  }

  @doc false
  def new(task, queue) do
    %__MODULE__{task: task, queue: queue, enqueued_at: System.system_time(:millisecond)}
  end
end
