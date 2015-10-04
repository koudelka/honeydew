defmodule Honeydew.WorkQueue do
  use GenServer
  require Logger
  alias Honeydew.Job

  # after max_failures, delay the job by delay_secs
  defmodule State do
    defstruct max_failures: nil,
              delay_secs: nil,
              suspended: false,
              queue: :queue.new, # jobs waiting to be taken by a worker
              backlog: MapSet.new, # jobs that have failed max_failures number of times, and are waiting to be re-queued after delay_secs
              waiting: :queue.new, # workers that are waiting for a job
              working: HashDict.new # workers that are currently working mapped to their current jobs
  end


  def start_link(name, max_failures, delay_secs) do
    GenServer.start_link(__MODULE__, %State{max_failures: max_failures, delay_secs: delay_secs}, name: name)
  end

  #
  # Messaging
  #

  def handle_cast({:add_task, task}, state) do
    job = %Job{task: task}
    {:noreply, queue_job(job, state)}
  end

  def handle_cast({:add_job, job}, state) do
    {:noreply, queue_job(job, state)}
  end

  def handle_cast(_msg, state), do: {:noreply, state}


  def handle_call({:add_task, task}, from, state) do
    job = %Job{task: task, from: from}
    handle_cast({:add_job, job}, state)
  end

  def handle_call(:job_please, from, %State{suspended: true} = state) do
    {:noreply, queue_worker(from, state)}
  end

  def handle_call(:job_please, {worker, _msg_ref} = from, state) do
    case :queue.out(state.queue) do
      # there's a job in the queue, honey do it, please!
      {{:value, job}, queue} ->
        {:reply, job, %{state | queue: queue, working: Dict.put(state.working, worker, job)}}
      # nothing for the worker to do right now, we'll get back to them later when something arrives
      {:empty, _} ->
        {:noreply, queue_worker(from, state)}
    end
  end

  def handle_call(:monitor_me, {worker, _msg_ref}, state) do
    Process.monitor(worker)
    {:reply, :ok, state}
  end

  def handle_call(:suspend, _from, state) do
    {:reply, :ok, %{state | suspended: true}}
  end

  def handle_call(:resume, _from, state) do
    state.queue
    |> :queue.to_list
    |> Enum.each &GenServer.cast(self, {:add_job, &1})

    {:reply, :ok, %{state | queue: :queue.new, suspended: false}}
  end

  def handle_call(:status, _from, state) do
    %State{queue: queue, backlog: backlog, working: working, waiting: waiting, suspended: suspended} = state

    status = %{
      queue: :queue.len(queue),
      backlog: Set.size(backlog),
      working: Dict.size(working),
      waiting: :queue.len(waiting),
      suspended: suspended
    }

    {:reply, status, state}
  end

  def handle_call(_msg, _from, state), do: {:reply, :ok, state}


  # A worker has died, put its job back on the queue and increment the job's "failures" count
  def handle_info({:DOWN, _ref, _type, worker_pid, _reason}, state) do
    case Dict.pop(state.working, worker_pid) do
      # worker wasn't working on anything
      {nil, _working} -> nil
      {job, working} ->
        state = %{state | working: working}
        job = %{job | failures: job.failures + 1}
        state = if job.failures < state.max_failures do
                  queue_job(job, state)
                else
                  # Logger.warn "[Honeydew] #{state.worker_module} Job failed too many times, delaying #{state.delay_secs}s: #{inspect job}"
                  delay_job(job, state)
                end
    end
    {:noreply, state}
  end

  # delay_secs has elapsed and a failing job is ready to be tried again
  def handle_info({:enqueue_delayed_job, job}, state) do
    Logger.info "[Honeydew] [#{__MODULE__}] Enqueuing delayed job: #{inspect job}"
    state = %{state | backlog: Set.delete(state.backlog, job)}
    {:noreply, queue_job(job, state)}
  end
  def handle_info(_msg, state), do: {:noreply, state}


  defp queue_job(job, %{suspended: true} = state) do
    %{state | queue: :queue.in(job, state.queue)}
  end

  defp queue_job(job, state) do
    case next_alive_worker(state.waiting) do
      # no workers are waiting, add the job to the queue
      {nil, waiting} ->
        %{state | queue: :queue.in(job, state.queue), waiting: waiting}
      # there's a worker waiting, give them the job
      {from_worker, waiting} ->
        {worker, _msg_ref} = from_worker
        GenServer.reply(from_worker, job)
        %{state | waiting: waiting, working: Dict.put(state.working, worker, job)}
    end
  end

  defp delay_job(job, state) do
    # random ids are needed so the backlog Set sees all jobs as unique
    job = %{job | id: :erlang.unique_integer}
    :erlang.send_after(state.delay_secs * 1000, self, {:enqueue_delayed_job, job})
    %{state | backlog: Set.put(state.backlog, job)}
  end

  defp queue_worker({worker, _msg_ref} = from, state) do
    %{state | waiting: :queue.in(from, state.waiting), working: Dict.delete(state.working, worker)}
  end

  defp next_alive_worker(waiting) do
    case :queue.out(waiting) do
      {{:value, from_worker}, waiting} ->
        {worker, _msg_ref} = from_worker
        if Process.alive? worker do
          {from_worker, waiting}
        else
          next_alive_worker(waiting)
        end
      {:empty, _} ->
        {nil, waiting}
    end
  end

end
