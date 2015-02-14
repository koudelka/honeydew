defmodule Honeydew.JobList do
  use GenServer
  require Logger
  alias Honeydew.Job

  defmodule State do
    defstruct jobs: :queue.new, waiting: :queue.new, working: HashDict.new, honey_module: nil, max_failures: nil
  end


  def start_link(honey_module, max_failures) do
    GenServer.start_link(__MODULE__, %State{honey_module: honey_module, max_failures: max_failures}, name: Honeydew.job_list(honey_module))
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
  def handle_call(_msg, _from, state), do: {:reply, :ok, state}

  # A honey has died, put its job back on the queue and increment the job's "failures" count
  def handle_info({:DOWN, _ref, _type, honey_pid, _reason}, state) do
    case Dict.pop(state.working, honey_pid) do
      # honey wasn't working on anything
      {nil, _working} -> nil
      {job, working} ->
        state = %{state | working: working}
        failures = job.failures + 1
        if failures < state.max_failures do
          state = add_job(%{job | failures: failures}, state)
        else
          Logger.warn "[Honeydew] #{state.honey_module} Job failed too many times: #{inspect job}"
        end
    end
    {:noreply, state}
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

  #
  # Testing Helpers
  #

  def backlog_length(pid) do
    %State{jobs: jobs} = :sys.get_state(pid)
    :queue.len(jobs)
  end

  def num_waiting_honeys(pid) do
    %State{waiting: waiting} = :sys.get_state(pid)
    :queue.len(waiting)
  end
end

