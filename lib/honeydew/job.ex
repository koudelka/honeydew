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
             :completed_at,
             {:delay_secs, 0}]

  @type t :: %__MODULE__{
    task: Honeydew.task,
    queue: Honeydew.queue_name,
    private: private,
    delay_secs: integer()
  }

  @doc false
  def new(task, queue) do
    %__MODULE__{task: task, queue: queue, enqueued_at: System.system_time(:millisecond)}
  end
end
