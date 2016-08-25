alias Experimental.GenStage

defmodule Honeydew.Queue do

  defmodule State do
    defstruct queue: nil,
      private: nil,
      outstanding: 0,
      suspended: false,
      failure_mode: nil
  end

  # @callback handle_demand(demand :: pos_integer, state :: %State{outstanding: 0}) :: {:noreply, [%Job{}] | [], %State{}}
  # @callback handle_cast({:enqueue, job :: %Job{}}, state :: %State{outstanding: 0})            :: {:noreply, [], %State{}}
  # @callback handle_cast({:enqueue, job :: %Job{}}, state :: %State{outstanding: pos_integer})  :: {:noreply, [%Job{}] | [], %State{}}
  # @callback handle_call({:enqueue, job :: %Job{}}, from :: {pid, reference}, state :: %State{}) :: {:noreply, [%Job{}] | [], %State{}}
  # @callback handle_cast({:ack,  job :: %Job{}}, state :: %State{})                     :: {:noreply, [], %State{}}
  # @callback handle_cast({:nack, job :: %Job{}, requeue :: boolean}, state :: %State{}) :: {:noreply, [], %State{}}
  # @optional_callbacks handle_call: 3

  defmacro __using__(_opts) do
    quote do
      use GenStage
      require Logger
      alias Honeydew.Monitor

      # @behaviour Honeydew.Queue
      @before_compile unquote(__MODULE__)

      def start_link(queue, args, dispatcher, failure_mode) do
        GenStage.start_link(__MODULE__, {queue, __MODULE__, args, dispatcher, failure_mode})
      end

      #
      # the worker module also has an init/1 that's called with a list, so we use a tuple
      # to ensure we match this one.
      #
      def init({queue, module, args, dispatcher, failure_mode}) do
        queue
        |> Honeydew.group(:queues)
        |> :pg2.join(self())

        with {:global, _name} <- queue,
          do: :ok = :net_kernel.monitor_nodes(true)

        queue
        |> Honeydew.get_all_members(:workers)
        |> subscribe_workers

        {:ok, state} = module.init(queue, args)

        {:producer, %State{queue: queue, private: state, failure_mode: failure_mode}, dispatcher: dispatcher}
      end

      def handle_cast(:"$honeydew.resume", %State{suspended: false} = state), do: {:noreply, [], state}
      def handle_cast(:"$honeydew.resume", %State{queue: queue} = state) do
        # handle_resume function instead?
        GenStage.cast(self(), :resume)

        {:noreply, [], %{state | suspended: false}}
      end

      def handle_cast(:"$honeydew.suspend", %State{suspended: true} = state), do: {:noreply, [], state}
      def handle_cast(:"$honeydew.suspend", state) do
        # handle_suspend function instead?
        GenStage.cast(self(), :suspend)

        {:noreply, [], %{state | suspended: true}}
      end

      # demand arrived while queue is suspended
      def handle_demand(demand, %State{suspended: true, outstanding: outstanding} = state) do
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      # demand arrived, but we still have unsatisfied demand
      def handle_demand(demand, %State{outstanding: outstanding} = state) when demand > 0 and outstanding > 0 do
        {:noreply, [], %{state | outstanding: outstanding + demand}}
      end

      def handle_call(:status, _from, %State{private: queue, suspended: suspended} = state) do
        status =
          queue
          |> status
          |> Map.put(:suspended, suspended)

        {:reply, status, [], state}
      end

      def handle_call({:filter, function}, _from, %State{private: queue} = state) do
        # try to prevent user code crashing the queue
        reply =
          try do
            {:ok, filter(queue, function)}
          rescue e ->
              {:error, e}
          end
        {:reply, reply, [], state}
      end

      def handle_call({:cancel, job}, _from, %State{private: queue} = state) do
        {reply, queue} = cancel(queue, job)
        {:reply, reply, [], %{state | private: queue}}
      end

      # debugging
      def handle_call(:"$honeydew.state", _from, state) do
        {:reply, state, [], state}
      end


      # when a node connects, ask it if it has any honeydew workers for this queue
      # we do it like this as there's a race condition between receiving this message
      # and :pg2 synchronizing groups
      def handle_info({:nodeup, node}, %State{queue: {:global, _} = queue} = state) do
        Logger.info "[Honeydew] Connection to #{node} established, looking for workers..."

        :rpc.async_call(node, :pg2, :get_local_members, [Honeydew.group(queue, :workers)])

        {:noreply, [], state}
      end

      def handle_info({:nodedown, node}, %State{queue: {:global, _} = queue} = state) do
        Logger.warn "[Honeydew] Lost connection to #{node}."
        {:noreply, [], state}
      end

      # rpc get-workers reply
      def handle_info({_promise_pid, {:promise_reply, {:error, {:no_such_group, _worker_group}}}}, state), do: {:noreply, [], state}
      def handle_info({_promise_pid, {:promise_reply, workers}}, state) do
        subscribe_workers(workers)
        {:noreply, [], state}
      end

      def start_monitor(job, %State{queue: queue, failure_mode: failure_mode}) do
        {:ok, pid} = Monitor.start(job, queue, failure_mode)
        %{job | monitor: pid}
      end

      defp subscribe_workers(workers) do
        Enum.each(workers, &GenStage.async_subscribe(&1, to: self(), max_demand: 1, min_demand: 0, cancel: :temporary))
      end
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      def handle_info(msg, state) do
        Logger.warn "[Honeydew] Queue #{inspect self()} received unexpected message #{inspect msg}"
        {:noreply, state}
      end
    end
  end

  def suspend(queue) do
    GenStage.cast(queue, :"$honeydew.suspend")
  end

  def resume(queue) do
    GenStage.cast(queue, :"$honeydew.resume")
  end
end
