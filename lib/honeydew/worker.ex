defmodule Honeydew.Worker do
  use GenServer
  require Logger

  def start_link(work_queue, worker_module, worker_init_args, retry_secs) do
    GenServer.start_link(__MODULE__, [work_queue, worker_module, worker_init_args, retry_secs])
  end

  def init([work_queue, worker_module, worker_init_args, retry_secs]) do
    Process.flag(:trap_exit, true)
    init_result = try do
                    apply(worker_module, :init, [worker_init_args])
                  rescue e ->
                    {:error, e}
                  end

    # consumes the possible DOWN message thrown by the worker module's init/0
    receive do
    after
      50 -> :ok
    end
    Process.flag(:trap_exit, false)

    case init_result do
      {:ok, state} ->
        GenServer.call(work_queue, :monitor_me)
        GenServer.cast(self, :ask_for_job)
        Logger.info("#{worker_module}.init/1 succeeded.")
        {:ok, {work_queue, worker_module, state}}
      error ->
        :timer.apply_after(retry_secs * 1000, Honeydew.Supervisor, :start_child, [worker_module, worker_init_args, retry_secs])
        Logger.warn("#{worker_module}.init/1 must return {:ok, state}, got: #{inspect(error)}, retrying in #{retry_secs}s")
        :ignore
    end
  end


  def handle_cast(:ask_for_job, {work_queue, worker_module, worker_state} = state) do
    job = GenServer.call(work_queue, :job_please, :infinity)
    result = case job.task do
               f when is_function(f) -> f.(worker_state)
               f when is_atom(f)     -> apply(worker_module, f, [worker_state])
               {f, a}                -> apply(worker_module, f, a ++ [worker_state])
             end

    if job.from do
      GenServer.reply(job.from, result)
    end

    GenServer.cast(self, :ask_for_job)
    {:noreply, state}
  end

end
