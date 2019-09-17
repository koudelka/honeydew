defmodule Honeydew do
  @moduledoc """
  A pluggable job queue + worker pool for Elixir.
  """

  alias Honeydew.Job
  alias Honeydew.JobMonitor
  alias Honeydew.Worker
  alias Honeydew.WorkerStarter
  alias Honeydew.WorkerGroupSupervisor
  alias Honeydew.Queue
  alias Honeydew.{Queues, Workers}
  require Logger

  @type mod_or_mod_args :: module | {module, args :: term}
  @type queue_name :: String.t | atom | {:global, String.t | atom}
  @type supervisor_opts :: Keyword.t
  @type async_opt :: {:reply, true} | {:delay_secs, pos_integer()}
  @type task :: {atom, [arg :: term]}
  @type filter :: (Job.t -> boolean) | atom

  @typedoc """
  Result of a `Honeydew.Job`
  """
  @type result :: term

  #
  # Parts of this module were lovingly stolen from
  # https://github.com/elixir-lang/elixir/blob/v1.3.2/lib/elixir/lib/task.ex#L320
  #

  @doc """
  Runs a task asynchronously.

  Raises a `RuntimeError` if `queue` process is not available.

  You can provide any of the following `opts`:

  - `reply`: returns the result of the job via `yield/1`, see below.
  - `delay_secs`: delays the execution of the job by the provided number of seconds.

  ## Examples

  To run a task asynchronously:

      Honeydew.async({:ping, ["127.0.0.1"]}, :my_queue)

  To run a task asynchronously and wait for result:

      # Without pipes
      job = Honeydew.async({:ping, ["127.0.0.1"]}, :my_queue, reply: true)
      Honeydew.yield(job)

      # With pipes
      :pong =
        {:ping, ["127.0.0.1"]}
        |> Honeydew.async(:my_queue, reply: true)
        |> Honeydew.yield()

  To run a task an hour later:

      Honeydew.async({:ping, ["127.0.0.1"]}, :my_queue, delay_secs: 60*60)
  """
  @spec async(task, queue_name, [async_opt]) :: Job.t | no_return
  def async(task, queue, opts \\ []) do
    job = Job.new(task, queue)

    {:ok, job} =
      opts
      |> Enum.reduce(job, fn
        {:reply, true}, job ->
          %Job{job | from: {self(), make_ref()}}

        {:delay_secs, secs}, job when is_integer(secs) and secs >= 0 ->
          %Job{job | delay_secs: secs}

        {:delay_secs, thing}, job ->
          raise ArgumentError, invalid_delay_secs_error(job, thing)
      end)
      |> enqueue

    job
  end

  @doc """
  Wait for a job to complete and return result.

  Returns the result of a job, or `nil` on timeout. Raises an `ArgumentError` if
  the job was not created with `reply: true` and in the current process.

  ## Example

  Calling `yield/2` with different timeouts.

      iex> job = Honeydew.async({:ping, ["127.0.0.1"]}, :my_queue, reply: true)
      iex> Honeydew.yield(job, 500) # Wait half a second
      nil
      # Result comes in at 1 second
      iex> Honeydew.yield(job, 1000) # Wait up to a second
      {:ok, :pong}
      iex> Honeydew.yield(job, 0)
      nil # <- because the message has already arrived and been handled

  The only time `yield/2` would ever return the result more than once is if
  the job executes more than once (as Honeydew aims for at-least-once
  execution).
  """
  @spec yield(Job.t, timeout) :: {:ok, result} | nil | no_return
  def yield(job, timeout \\ 5000)
  def yield(%Job{from: nil} = job, _), do: raise ArgumentError, reply_not_requested_error(job)
  def yield(%Job{from: {owner, _}} = job, _) when owner != self(), do: raise ArgumentError, invalid_owner_error(job)

  def yield(%Job{from: {_, ref}}, timeout) do
    receive do
      %Job{from: {_, ^ref}, result: result} ->
        result # may be {:ok, term} or {:exit, term}
    after
      timeout ->
        nil
    end
  end

  @doc """
  Suspends job processing for a queue.
  """
  @spec suspend(queue_name) :: :ok
  def suspend(queue) do
    queue
    |> get_all_members(Queues)
    |> Enum.each(&Queue.suspend/1)
  end

  @doc """
  Resumes job processing for a queue.
  """
  @spec resume(queue_name) :: :ok
  def resume(queue) do
    queue
    |> get_all_members(Queues)
    |> Enum.each(&Queue.resume/1)
  end



  @doc """
  Returns the currrent status of the queue and all attached workers.

  You can provide any of the following `opts`:

  - `timeout`: specifies the time (in miliseconds) the calling process will wait for the queue to return the status,
               note that this timeout does not cancel the status callback execution in the queue.
  """
  @type status_opt :: {:timeout, pos_integer}
  @spec status(queue_name, [status_opt]) :: map()
  def status(queue, opts \\ []) do
    queue_status =
      queue
      |> get_queue
      |> Queue.status(opts)

    busy_workers =
      queue_status
      |> Map.get(:job_monitors)
      |> Enum.map(fn monitor ->
           try do
             JobMonitor.status(monitor)
           catch
             # the monitor may have shut down
             :exit, _ -> nil
           end
         end)
      |> Enum.reject(&(!&1))
      |> Enum.into(%{})

    workers =
      queue
      |> get_all_members(Workers)
      |> Enum.map(&{&1, nil})
      |> Enum.into(%{})
      |> Map.merge(busy_workers)

    %{queue: Map.delete(queue_status, :job_monitors), workers: workers}
  end

  @doc """
  Filters the jobs currently on the queue.

  Filtration support depends on the queue implementation.

  ErlangQueue and Mnesia queues support filtering with functions.

  Ecto Poll Queues have pre-defined, named filters. At the moment, only `:abandoned` is implemented.

  Note:
  - This function returns a `List`, not a `Stream`, so calling it can be memory intensive when invoked on a large queue.
  - The filtration is done by the queue process, not the client, so a heavy filter will tie up the queue.

  ## Examples

  Filter jobs with a specific task.

      Honeydew.filter(:my_queue, &match?(%Honeydew.Job{task: {:ping, _}}, &1)) # ErlangQueue or Mnesia

      Honeydew.filter(:my_queue, %{task: {:ping, ["127.0.0.1"]}}) # Mnesia

      Honeydew.filter(:my_queue, :abandoned) # Ecto queue

  Return all jobs.

      Honeydew.filter(:my_queue, fn _ -> true end)
  """
  @spec filter(queue_name, filter) :: [Job.t]
  def filter(queue, filter) do
    {:ok, jobs} =
      queue
      |> get_queue
      |> Queue.filter(filter)

    jobs
  end

  @doc """
  Cancels a job.

  The return value depends on the status of the job.

  * `:ok` - Job had not been started and was able to be cancelled.
  * `{:error, :in_progress}` - Job was in progress and unable to be cancelled.
  * `{:error, :not_found}` - Job was not found on the queue (or already processed) and was unable to be cancelled.
  """
  @spec cancel(Job.t) :: :ok | {:error, :in_progress} | {:error, :not_found}
  def cancel(%Job{queue: queue} = job) do
    queue
    |> get_queue
    |> Queue.cancel(job)
  end

  @doc """
  Cancels the job associated with the first argument.

  For example, for the Ecto Poll Queue, the first argument is the value of an ID from your schema.

  The return value depends on the status of the job.

  * `:ok` - Job had not been started and was able to be cancelled.
  * `{:error, :in_progress}` - Job was in progress and unable to be cancelled, the Ecto Poll Queue does not support this return.
  * `{:error, :not_found}` - Job was not found on the queue (or already processed) and was unable to be cancelled.
  """
  @spec cancel(Job.private(), queue_name) :: :ok | {:error, :in_progress} | {:error, :not_found}
  def cancel(private, queue) do
    %Job{private: private, queue: queue} |> cancel
  end

  @doc """
  Moves a job to another queue.

  Raises a `RuntimeError` if `to_queue` is not available.

  This function first enqueues the job on `to_queue`, and then tries to
  cancel it on its current queue. This means there's a possiblity a job could
  be processed on both queues. This behavior is consistent with Honeydew's
  at-least-once execution goal.

  This function is most helpful on a queue where there a no workers
  (like a dead letter queue), because the job won't be processed out from under
  the queue.
  """
  @spec move(Job.t, to_queue :: queue_name) :: Job.t | no_return
  def move(%Job{} = job, to_queue) do
    {:ok, new_job} = enqueue(%Job{job | queue: to_queue})

    # Don't worry if it fails to cancel.
    cancel(job)

    new_job
  end

  @doc false
  def enqueue(%Job{queue: queue} = job) do
    queue
    |> get_queue
    |> case do
         nil -> raise RuntimeError, no_queues_running_error(job)
         queue -> queue
       end
    |> Queue.enqueue(job)
  end

  @doc false
  def invalid_owner_error(job) do
    "job #{inspect job} must be queried from the owner but was queried from #{inspect self()}"
  end

  @doc false
  def invalid_delay_secs_error(job, secs) do
    "invalid :delay_secs argument, #{inspect secs}, provided for job #{inspect job}, must be a non-negative integer"
  end

  @doc false
  def reply_not_requested_error(job) do
    "job #{inspect job} didn't request a reply when enqueued, set `:reply` to `true`, see `async/3`"
  end

  @doc false
  def no_queues_running_error(%Job{queue: {:global, _} = queue} = job) do
    "can't enqueue job because there aren't any queue processes running for the distributed queue `#{inspect queue}, are you connected to the cluster? #{inspect job} `"
  end

  @doc false
  def no_queues_running_error(%Job{queue: queue} = job) do
    "can't enqueue job #{inspect job} because there aren't any queue processes running for `#{inspect queue}`"
  end

  @deprecated "Honeydew now supervises your queue processes, please use `Honeydew.start_queue/2 instead.`"
  def queue_spec(_name, _opts) do
    raise "Honeydew now supervises your queue processes, please use `Honeydew.start_queue/2 instead.`"
  end

  @doc """
  Returns a list of queues running on this node.
  """
  @spec queues() :: [queue_name]
  defdelegate queues(), to: Queues

  @doc """
  Returns a list of queues that have workers are running on this node.
  """
  @spec workers() :: [queue_name]
  defdelegate workers(), to: Workers

  @type queue_spec_opt ::
  {:queue, mod_or_mod_args} |
  {:dispatcher, mod_or_mod_args} |
  {:failure_mode, mod_or_mod_args | nil} |
  {:success_mode, mod_or_mod_args | nil} |
  {:supervisor_opts, supervisor_opts} |
  {:suspended, boolean}

  @doc """
  Starts a queue under Honeydew's supervision tree.

  `name` is how you'll refer to the queue to add a task.

  You can provide any of the following `opts`:

  - `queue`: is the module that queue will use. Defaults to
    `Honeydew.Queue.ErlangQueue`. You may also provide args to the queue's
    `c:Honeydew.Queue.init/2` callback using the following format:
    `{module, args}`.
  - `dispatcher`: the job dispatching strategy, `{module, init_args}`.

  - `failure_mode`: the way that failed jobs should be handled. You can pass
    either a module, or `{module, args}`. The module must implement the
    `Honeydew.FailureMode` behaviour. Defaults to
    `{Honeydew.FailureMode.Abandon, []}`.

  - `success_mode`: a callback that runs when a job successfully completes. You
     can pass either a module, or `{module, args}`. The module must implement
     the `Honeydew.SuccessMode` behaviour. Defaults to `nil`.

  - `suspended`: Start queue in suspended state. Defaults to `false`.

  For example:

  - `Honeydew.start_queue("my_awesome_queue")`

  - `Honeydew.start_queue("my_awesome_queue", queue: {MyQueueModule, [ip: "localhost"]},
                                              dispatcher: {Honeydew.Dispatcher.MRU, []})`

  Note that the `failure_mode` or `success_mode` handler is run in the job's
  dedicated monitor process. This means the handlers for multiple jobs can run
  concurrently, but they can also crash that process.
  """
  @spec start_queue(queue_name, [queue_spec_opt]) :: :ok | {:error, term()}
  defdelegate start_queue(name, opts \\ []), to: Queues

  @doc """
  Stops the local instance of the provided queue name.
  """
  @spec stop_queue(queue_name) :: :ok | {:error, :not_running}
  defdelegate stop_queue(name), to: Queues

  @type worker_opt ::
    {:num, non_neg_integer} |
    {:init_retry_secs, pos_integer} |
    {:shutdown, non_neg_integer} |
    {:nodes, [node]}

  @type worker_opts :: [worker_opt]

  @doc """
  Starts workers under Honeydew's supervision tree.

  `name` is the name of the queue that the workers pull jobs from.

  `module` is the module that the workers in your queue will use. You may also
  provide `c:Honeydew.Worker.init/1` args with `{module, args}`.

  You can provide any of the following `opts`:

  - `num`: the number of workers to start. Defaults to `10`.

  - `init_retry_secs`: the amount of time, in seconds, a stateful worker waits
  before trying to re-initialize after its `c:Honeydew.Worker.init/1` function
  fails. You can also override this behavior by implementing the
  `c:Honeydew.Worker.init_failed/0` callback, see `README/workers.md`.

  - `shutdown`: if a worker is in the middle of a job, the amount of time, in
  milliseconds, to wait before brutally killing it. Defaults to `10_000`.

  - `nodes`: for :global queues, you can provide a list of nodes to stay
     connected to (your queue node and enqueuing nodes). Defaults to `[]`.

  For example:

  - `Honeydew.start_workers("my_awesome_queue", MyJobModule)`

  - `Honeydew.start_workers("my_awesome_queue", {MyJobModule, [key: "secret key"]}, num: 3)`

  - `Honeydew.start_workers({:global, "my_awesome_queue"}, MyJobModule, nodes: [:clientfacing@dax, :queue@dax])`
  """
  defdelegate start_workers(name, module_and_args, opts \\ []), to: Honeydew.Workers

  @deprecated "Honeydew now supervises your worker processes, please use `Honeydew.start_workers/3 instead.`"
  def worker_spec(_queue, _module_and_args, _opts) do
    raise "Honeydew now supervises your worker processes, please use `Honeydew.start_workers/3 instead.`"
  end

  @doc """
  Stops the local workers for the provided queue name.
  """
  @spec stop_workers(queue_name) :: :ok | {:error, :not_running}
  defdelegate stop_workers(name), to: Workers

  @doc """
  Re-initializes the given worker, this is intended to be used from
  within a worker's `c:Honeydew.Worker.failed_init/0` callback. Using it otherwise
  may cause undefined behavior, at present, don't do it.
  """
  @spec reinitialize_worker() :: :ok
  def reinitialize_worker do
    Worker.module_init(self())
  end

  @groups [Workers, Queues]

  Enum.each(@groups, fn group ->
    @doc false
    def group(queue, unquote(group)) do
      name(queue, unquote(group))
    end
  end)

  @processes [WorkerGroupSupervisor, WorkerStarter]

  Enum.each(@processes, fn process ->
    @doc false
    def process(queue, unquote(process)) do
      name(queue, unquote(process))
    end
  end)


  @doc false
  def create_groups(queue) do
    Enum.each(@groups, fn name ->
      queue |> group(name) |> :pg2.create
    end)
  end

  @doc false
  def delete_groups(queue) do
    Enum.each(@groups, fn name ->
      queue |> group(name) |> :pg2.delete
    end)
  end

  @doc false
  def get_all_members({:global, _} = queue, name) do
    queue |> group(name) |> :pg2.get_members
  end

  @doc false
  def get_all_members(queue, name) do
    get_all_local_members(queue, name)
  end

  # we need to know local members to shut down local components
  @doc false
  def get_all_local_members(queue, name) do
    queue |> group(name) |> :pg2.get_local_members
  end


  @doc false
  def get_queue(queue) do
    queue
    |> get_all_queues
    |> case do
         {:error, {:no_such_group, _queue}} -> []
         queues -> queues
       end
    |> List.first
  end

  @doc false
  def get_all_queues({:global, _name} = queue) do
    queue
    |> group(Queues)
    |> :pg2.get_members
  end

  @doc false
  def get_all_queues(queue) do
    queue
    |> group(Queues)
    |> :pg2.get_local_members
  end

  @doc false
  def table_name({:global, queue}) do
    "global_#{queue}"
  end

  @doc false
  def table_name(queue) do
    to_string(queue)
  end

  defp name({:global, queue}, component) do
    name([:global, queue], component)
  end

  defp name(queue, component) do
    [component, queue] |> List.flatten |> Enum.join(".") |> String.to_atom
  end

  @doc false
  defmacro debug(ast) do
    quote do
      fn ->
        Logger.debug unquote(ast)
      end
    end
  end

end
