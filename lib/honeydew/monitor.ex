defmodule Honeydew.Monitor do
  use GenServer
  require Logger

  # when the queue casts a job to a worker, it spawns a local Monitor with the job as state,
  # the Monitor watches the worker, if the worker dies (or its node is disconnected), the Monitor returns the
  # job to the queue. it waits @claim_delay miliseconds for the worker to confirm receipt of the job.

  @claim_delay 5_000 # ms

  defmodule State do
    defstruct [:queue, :worker, :job, :failure_mode]
  end

  def start(job, queue, failure_mode) do
    GenServer.start(__MODULE__, [job, queue, failure_mode])
  end

  def init([job, queue, failure_mode]) do
    Process.send_after(self(), :return_job, @claim_delay)

    {:ok, %State{job: job, queue: queue, failure_mode: failure_mode}}
  end

  def handle_call({:claim, job}, {worker, _ref}, state) do
    Logger.debug "[Honeydew] Monitor #{inspect self()} had job #{inspect job.private} claimed by worker #{inspect worker}"
    Process.monitor(worker)
    {:reply, :ok, %{state | job: job, worker: worker}}
  end

  def handle_call(:current_job, _from, %State{job: job, worker: worker} = state) do
    {:reply, {worker, job}, state}
  end

  def handle_call(:ack, {worker, _ref}, %State{job: job, queue: queue, worker: worker} = state) do
    queue
    |> Honeydew.get_queue
    |> GenServer.cast({:ack, job})

    {:stop, :normal, :ok, %{state | job: nil}}
  end

  # no worker has claimed the job, return it
  def handle_info(:return_job, %State{job: job, queue: queue, worker: nil} = state) do
    queue
    |> Honeydew.get_queue
    |> GenServer.cast({:nack, job})

    {:stop, :normal, %{state | job: nil}}
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
