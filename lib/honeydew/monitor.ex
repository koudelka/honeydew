defmodule Honeydew.Monitor do
  use GenServer
  require Logger
  alias Honeydew.FailureMode.Requeue

  # when the queue puts a job in the genstage pipeline, it spawns a local Monitor with the job as state,
  # the Monitor watches the worker, if the worker dies (or its node is disconnected), the Monitor returns the
  # job to the queue. since the monitor doesn't know which worker is going to get the job, it waits for a worker
  # to claim the jobs, if it doesn't hear from a worker within @claim_delay miliseconds, it assumes the job was lost
  # in transit (maybe the worker crashed before the Monitor could watch it, or maybe a node disconnected)

  @claim_delay 5_000 # ms

  defmodule State do
    defstruct [:queue, :worker, :job, :failure_mode]
  end

  def start(job, queue, failure_mode) do
    GenServer.start(__MODULE__, [job, queue, failure_mode])
  end

  def init([job, queue, failure_mode]) do
    Process.flag(:trap_exit, true)

    queue
    |> Honeydew.group(:monitors)
    |> :pg2.join(self())

    Process.send_after(self(), :return_job, @claim_delay)

    {:ok, %State{job: job, queue: queue, failure_mode: failure_mode}}
  end

  def handle_call({:claim, job}, {worker, _ref}, state) do
    Process.monitor(worker)
    {:reply, :ok, %{state | job: job, worker: worker}}
  end

  def handle_call(:current_job, _from, %State{job: job, worker: worker} = state) do
    {:reply, {worker, job}, state}
  end

  def handle_call(:ack, {worker, _ref}, %State{job: job, queue: queue, worker: worker} = state) do
    queue
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, job})

    {:stop, :normal, :ok, %{state | job: nil}}
  end

  # no worker has claimed the job, return it
  def handle_info(:return_job, %State{job: job, queue: queue, worker: nil} = state) do
    # TODO: shouldn't use this failure mode, it'll requeue the job at the end of the queue, need to nack it instead
    queue
    |> Honeydew.get_queue
    |> GenStage.cast({:ack, job})

    Requeue.handle_failure(job, :not_claimed, queue: queue)
    {:stop, :not_claimed, %{state | job: nil}}
  end
  def handle_info(:return_job, state), do: {:noreply, state}

  # worker died while busy
  def handle_info({:DOWN, _ref, :process, worker, reason}, %State{worker: worker, job: job, failure_mode: {failure_mode, failure_mode_args}} = state) do
    failure_mode.handle_failure(job, reason, failure_mode_args)

    {:stop, :normal, %{state | job: nil}}
  end

  def handle_info(msg, state) do
    Logger.warn "[Honeydew] Monitor #{inspect self()} received unexpected message #{inspect msg}"
    {:noreply, state}
  end

end
