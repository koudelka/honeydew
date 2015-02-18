defmodule Honeydew.JobList do
  use GenServer
  require Logger
  alias Honeydew.Job

  # after max_failures, delay the job by delay_secs
  defmodule State do
    defstruct honey_module: nil,
              max_failures: nil,
              delay_secs: nil,
              jobs: :queue.new, # jobs waiting to be taken by a honey
              backlog: HashSet.new, # jobs that have failed max_failures number of times, and are waiting to be re-queued after delay_secs
              waiting: :queue.new, # honeys that are waiting for a job
              working: HashDict.new # honeys that are currently working mapped to their current jobs
  end


  def start_link(honey_module, max_failures, delay_secs) do
    GenServer.start_link(__MODULE__, %State{honey_module: honey_module, max_failures: max_failures, delay_secs: delay_secs}, name: Honeydew.job_list(honey_module))
  end

  #
  # Messaging
  #

  def handle_cast({:add_task, task}, state) do
    job = %Job{task: task}
    {:noreply, add_job(job, state)}
  end
  def handle_cast(_msg, state), do: {:noreply, state}


  def handle_call({:add_task, task}, from, state) do
    job = %Job{task: task, from: from}
    {:noreply, add_job(job, state)}
  end

  def handle_call(:job_please, from_honey, state) do
    {honey, _msg_ref} = from_honey
    case :queue.out(state.jobs) do
      # there's a job in the jobs, honey do it, please!
      {{:value, job}, jobs} ->
        {:reply, job, %{state | jobs: jobs, working: Dict.put(state.working, honey, job)}}
      # nothing for honey to do right now, we'll get back to them later
      {:empty, _} ->
        {:noreply, %{state | waiting: :queue.in(from_honey, state.waiting), working: Dict.delete(state.working, honey)}}
    end
  end

  def handle_call(:monitor_me, from_honey, state) do
    {honey, _msg_ref} = from_honey
    Process.monitor(honey)
    {:reply, nil, state}
  end

  def handle_call(:status, _from, state) do
    %State{jobs: jobs, backlog: backlog, working: working, waiting: waiting} = state

    status = %{
       jobs: :queue.len(jobs),
       backlog: Set.size(backlog),
       working: Dict.size(working),
       waiting: :queue.len(waiting)
    }

    {:reply, status, state}
  end

  def handle_call(_msg, _from, state), do: {:reply, :ok, state}


  # A honey has died, put its job back on the queue and increment the job's "failures" count
  def handle_info({:DOWN, _ref, _type, honey_pid, _reason}, state) do
    case Dict.pop(state.working, honey_pid) do
      # honey wasn't working on anything
      {nil, _working} -> nil
      {job, working} ->
        state = %{state | working: working}
        job = %{job | failures: job.failures + 1}
        state = \
          if job.failures < state.max_failures do
            add_job(job, state)
          else
            Logger.warn "[Honeydew] #{state.honey_module} Job failed too many times, delaying #{state.delay_secs}s: #{inspect job}"
            delay_job(job, state)
          end
    end
    {:noreply, state}
  end

  # delay_secs has elapsed and a failing job is ready to be tried again
  def handle_info({:enqueue_delayed_job, job}, state) do
    Logger.info "[Honeydew] [#{__MODULE__}] Enqueuing delayed job: #{inspect job}"
    state = %{state | backlog: Set.delete(state.backlog, job)}
    {:noreply, add_job(job, state)}
  end
  def handle_info(_msg, state), do: {:noreply, state}


  defp add_job(job, state) do
    case next_alive_honey(state.waiting) do
      # no honeys are waiting, add the job to the backlog
      {nil, waiting} ->
        %{state | jobs: :queue.in(job, state.jobs), waiting: waiting}
      # there's a honey waiting, give them the job
      {from_honey, waiting} ->
        {honey, _msg_ref} = from_honey
        GenServer.reply(from_honey, job)
        %{state | waiting: waiting, working: Dict.put(state.working, honey, job)}
    end
  end

  defp delay_job(job, state) do
    # random ids are needed so the backlog HashSet sees all jobs as unique
    delay_id = [:random.uniform(100_000), :random.uniform(100_000)] ++ Tuple.to_list(:erlang.now)
    job = %{job | id: delay_id}
    :erlang.send_after(state.delay_secs * 1000, self, {:enqueue_delayed_job, job})
    %{state | backlog: Set.put(state.backlog, job)}
  end

  defp next_alive_honey(waiting) do
    case :queue.out(waiting) do
      {{:value, from_honey}, waiting} ->
        {honey, _msg_ref} = from_honey
        if Process.alive? honey do
          {from_honey, waiting}
        else
          next_alive_honey(waiting)
        end
      {:empty, _} ->
        {nil, waiting}
    end
  end

end

