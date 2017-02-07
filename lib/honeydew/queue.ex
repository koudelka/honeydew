defmodule Honeydew.Queue do

  defmodule State do
    defstruct queue: nil,
      private: nil,
      dispatcher: nil,
      suspended: false,
      failure_mode: nil
  end

  defmacro __using__(_opts) do
    quote do
      use GenServer
      require Logger
      alias Honeydew.Monitor

      # @behaviour Honeydew.Queue
      @before_compile unquote(__MODULE__)

      def start_link(queue, args, dispatcher, failure_mode) do
        GenServer.start_link(__MODULE__, {queue, args, dispatcher, failure_mode})
      end

      #
      # the queue module also has an init/1 that's called with a list, so we use a tuple
      # to ensure we match this one.
      #
      def init({queue, args, {dispatcher, dispatcher_args}, failure_mode}) do
        queue
        |> Honeydew.group(:queues)
        |> :pg2.join(self())

        with {:global, _name} <- queue,
          do: :ok = :net_kernel.monitor_nodes(true)

        queue
        |> Honeydew.get_all_members(:workers)
        |> subscribe_workers

        {:ok, state} = init(queue, args)

        {:ok, dispatcher_private} = :erlang.apply(dispatcher, :init, dispatcher_args)

        {:ok, %State{queue: queue, private: state, failure_mode: failure_mode, dispatcher: {dispatcher, dispatcher_private}}}
      end

      #
      # Enqueue/Reserve
      #

      def handle_call({:enqueue, job}, _from, %State{suspended: true} = state) do
        {state, job} = enqueue(state, job)
        {:reply, {:ok, job}, state}
      end

      def handle_call({:enqueue, job}, _from, state) do
        {state, job} = enqueue(state, job)
        {:reply, {:ok, job}, dispatch(state)}
      end

      def handle_cast({:worker_ready, worker}, state) do
        Logger.debug "[Honeydew] Queue #{inspect self()} ready for worker #{inspect worker}"
        Process.monitor(worker)

        state =
          state
          |> check_in_worker(worker)
          |> dispatch
        {:noreply, state}
      end

      #
      # Ack/Nack
      #

      def handle_cast({:ack, job}, state) do
        Logger.debug "[Honeydew] Job #{inspect job.private} acked in #{inspect self()}"
        {:noreply, state |> ack(job)}
      end

      def handle_cast({:nack, job}, state) do
        Logger.debug "[Honeydew] Job #{inspect job.private} nacked by #{inspect self()}"
        {:noreply, state |> nack(job) |> dispatch}
      end

      #
      # Suspend/Resume
      #

      def handle_cast(:resume, %State{suspended: false} = state), do: {:noreply, state}
      def handle_cast(:resume, %State{queue: queue} = state) do
        # resume(state)

        {:noreply, dispatch(%{state | suspended: false})}
      end

      def handle_cast(:suspend, %State{suspended: true} = state), do: {:noreply, state}
      def handle_cast(:suspend, state) do
        # suspend(state)

        {:noreply, %{state | suspended: true}}
      end

      def handle_call(:status, _from, %State{private: queue, suspended: suspended} = state) do
        status =
          queue
          |> status
          |> Map.put(:suspended, suspended)

        {:reply, status, state}
      end

      def handle_call({:filter, function}, _from, %State{private: queue} = state) do
        # try to prevent user code crashing the queue
        reply =
          try do
            {:ok, filter(queue, function)}
          rescue e ->
              {:error, e}
          end
        {:reply, reply, state}
      end

      def handle_call({:cancel, job}, _from, %State{private: queue} = state) do
        {reply, queue} = cancel(queue, job)
        {:reply, reply, %{state | private: queue}}
      end

      # debugging
      def handle_call(:"$honeydew.state", _from, state) do
        {:reply, state, state}
      end

      #
      # Worker Discovery
      #

      # when a node connects, ask it if it has any honeydew workers for this queue
      # we do it like this as there's a race condition between receiving this message
      # and :pg2 synchronizing groups
      def handle_info({:nodeup, node}, %State{queue: {:global, _} = queue} = state) do
        Logger.info "[Honeydew] Connection to #{node} established, looking for workers..."

        :rpc.async_call(node, :pg2, :get_local_members, [Honeydew.group(queue, :workers)])

        {:noreply, state}
      end

      def handle_info({:nodedown, node}, %State{queue: {:global, _} = queue} = state) do
        Logger.warn "[Honeydew] Lost connection to #{node}."
        {:noreply, state}
      end

      # rpc get-workers reply
      def handle_info({_promise_pid, {:promise_reply, {:error, {:no_such_group, _worker_group}}}}, state), do: {:noreply, state}
      def handle_info({_promise_pid, {:promise_reply, workers}}, state) do
        Logger.debug "[Honeydew] Found #{Enum.count(workers)} workers."
        subscribe_workers(workers)
        {:noreply, state}
      end


      def handle_info({:DOWN, _ref, :process, worker, _reason}, state) do
        Logger.debug "[Honeydew] Queue #{inspect self()} saw worker #{inspect worker} crash"
        {:noreply, remove_worker(state, worker)}
      end

      def start_monitor(job, %State{queue: queue, failure_mode: failure_mode}) do
        {:ok, pid} = Monitor.start(job, queue, failure_mode)
        %{job | monitor: pid}
      end

      defp subscribe_workers(workers) do
        Enum.each(workers, &GenServer.cast(&1, :subscribe_to_queues))
      end

      defp send_job(worker, job, %State{queue: queue, failure_mode: failure_mode}) do
        {:ok, pid} = Monitor.start(job, queue, failure_mode)
        job = %{job | monitor: pid}
        GenServer.cast(worker, {:run, job})
      end

      defp dispatch(state) do
        with true <- worker_available?(state),
             {state, job} <- reserve(state),
             {worker, state} when not is_nil(worker) <- check_out_worker(job, state) do
          Logger.debug "[Honeydew] Queue #{inspect self()} dispatching job #{inspect job.private} to #{inspect worker}"
          send_job(worker, job, state)
          dispatch(state)
        else _ -> state
        end
      end

      defp worker_available?(%State{dispatcher: {dispatcher, dispatcher_private}}) do
        dispatcher.available?(dispatcher_private)
      end

      defp check_out_worker(job, %State{dispatcher: {dispatcher, dispatcher_private}} = state) do
        {worker, dispatcher_private} = dispatcher.check_out(job, dispatcher_private)
        {worker, %{state | dispatcher: {dispatcher, dispatcher_private}}}
      end

      defp check_in_worker(%State{dispatcher: {dispatcher, dispatcher_private}} = state, worker) do
        dispatcher_private = dispatcher.check_in(worker, dispatcher_private)
        %{state | dispatcher: {dispatcher, dispatcher_private}}
      end

      defp remove_worker(%State{dispatcher: {dispatcher, dispatcher_private}} = state, worker) do
        dispatcher_private = dispatcher.remove(worker, dispatcher_private)
        %{state | dispatcher: {dispatcher, dispatcher_private}}
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
end
