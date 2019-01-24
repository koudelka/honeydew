defmodule Honeydew.JobRunner do
  use GenServer
  require Logger
  require Honeydew

  alias Honeydew.Job
  alias Honeydew.Crash
  alias Honeydew.Worker

  @doc false
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  defmodule State do
    @moduledoc false

    defstruct [:worker, :job, :module, :worker_private]
  end


  #
  # Internal API
  #

  def run_link(job, module, worker_private) do
    GenServer.start_link(__MODULE__, [self(), job, module, worker_private])
  end

  @impl true
  def init([worker, %Job{job_monitor: job_monitor} = job, module, worker_private]) do
    Process.put(:job_monitor, job_monitor)

    {:ok, %State{job: job,
                 module: module,
                 worker: worker,
                 worker_private: worker_private}, {:continue, :run}}
  end

  defp do_run(%State{job: %Job{task: task} = job,
                     module: module,
                     worker: worker,
                     worker_private: worker_private} = state) do
    private_args =
      case worker_private do
        {:state, s} -> [s]
        :no_state   -> []
      end

    result =
      try do
        result =
          case task do
            f when is_function(f) -> apply(f, private_args)
            f when is_atom(f)     -> apply(module, f, private_args)
            {f, a}                -> apply(module, f, a ++ private_args)
          end
        {:ok, result}
      rescue e ->
        {:error, Crash.new(:exception, e, System.stacktrace())}
      catch
        :exit, reason ->
          # catch exit signals and shut down in an orderly manner
          {:error, Crash.new(:exit, reason)}
        e ->
          {:error, Crash.new(:throw, e, System.stacktrace())}
      end

    :ok = Worker.job_finished(worker, %{job | result: result})

    state
  end


  @impl true
  def handle_continue(:run, state) do
    {:stop, :normal, do_run(state)}
  end

  @impl true
  def terminate(:normal, _state), do: :ok
  def terminate(:shutdown, _state), do: :ok
  def terminate({:shutdown, _}, _state), do: :ok
  def terminate(reason, _state) do
    Logger.info "[Honeydew] JobRunner #{inspect self()} stopped because #{inspect reason}"
  end
end
