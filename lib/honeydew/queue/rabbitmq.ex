if Code.ensure_loaded?(AMQP) do
  defmodule Honeydew.Queue.RabbitMQ do
    use Honeydew.Queue
    alias AMQP.{Connection, Channel, Queue, Basic}
    alias Honeydew.Job
    alias Honeydew.Queue.State

    # private state
    defmodule PState do
      defstruct channel: nil,
        exchange: nil,
        name: nil,
        consumer_tag: nil
    end

    def init(queue_name, [conn_args, opts]) do
      durable = Keyword.get(opts, :durable, true)
      exchange = opts[:exchange] || ""
      prefetch = opts[:prefetch] || 10

      {:ok, conn} = Connection.open(conn_args)
      Process.link(conn.pid)

      {:ok, channel} = Channel.open(conn)
      Queue.declare(channel, queue_name, durable: durable)
      Basic.qos(channel, prefetch_count: prefetch)

      {:ok, %PState{channel: channel, exchange: exchange, name: queue_name}}
    end

    # GenStage Callbacks

    #
    # After all outstanding demand has been satisfied, Start consuming events when we receive demand
    # This is also our initial state when the queue process starts up.
    #
    def handle_demand(demand, %State{private: queue, outstanding: 0} = state) when demand > 0 do
      {queue, jobs} = reserve_or_subscribe(queue, demand)
      {:noreply, jobs, %{state | private: queue, outstanding: demand - Enum.count(jobs)}}
    end

    # Enqueuing

    def handle_call({:enqueue, job}, _from, %State{private: queue} = state) do
      Basic.publish(queue.channel, queue.exchange, queue.name, :erlang.term_to_binary(job), persistent: true)
      {:reply, job, [], state}
    end

    def handle_cast({:ack, job}, %State{private: queue} = state) do
      ack(queue, job)
      {:noreply, [], state}
    end

    def handle_cast({:nack, job}, %State{private: queue} = state) do
      nack(queue, job)
      {:noreply, [], state}
    end

    def handle_cast(:suspend, %State{private: %PState{consumer_tag: consumer_tag}} = state) when is_nil(consumer_tag) do
      {:noreply, [], state}
    end

    def handle_cast(:suspend, %State{private: %PState{channel: channel,
                                                      consumer_tag: consumer_tag} = queue} = state) do
      Basic.cancel(channel, consumer_tag)

      {:noreply, [], %{state | private: %{queue | consumer_tag: nil}}}
    end

    def handle_cast(:resume, %State{private: queue, outstanding: outstanding} = state) do
      {queue, jobs} = reserve_or_subscribe(queue, outstanding)
      {:noreply, jobs, %{state | private: queue, outstanding: outstanding - Enum.count(jobs)}}
    end


    def handle_info({:basic_deliver, _payload, %{delivery_tag: delivery_tag}}, %State{private: %PState{channel: channel}, outstanding: 0} = state) do
      Basic.reject(channel, delivery_tag, redeliver: true)
      {:noreply, [], state}
    end

    def handle_info({:basic_deliver, _payload, meta}, %State{private: queue, suspended: true} = state) do
      nack(queue, meta)
      {:noreply, [], state}
    end

    def handle_info({:basic_deliver, payload, meta}, %State{private: %PState{channel: channel,
                                                                            consumer_tag: consumer_tag} = queue, outstanding: 1} = state) do
      Basic.cancel(channel, consumer_tag)
      state = %{state | private: %{queue | consumer_tag: nil}}
      dispatch(payload, meta, state)
    end

    def handle_info({:basic_deliver, payload, meta}, state) do
      dispatch(payload, meta, state)
    end

    def handle_info({:basic_consume_ok, _meta}, state), do: {:noreply, [], state}
    def handle_info({:basic_cancel, _meta}, state), do: {:stop, :normal, state}
    def handle_info({:basic_cancel_ok, _meta}, state), do: {:noreply, [], state}


    def status(%PState{channel: channel, name: name, consumer_tag: consumer_tag}) do
      %{count: Queue.message_count(channel, name),
        subscribed?: consumer_tag != nil}
    end

    # TODO: DRY via exception
    def filter(_, _), do: raise "RabbitMQ doesn't support this function."
    def cancel(_, _), do: raise "RabbitMQ doesn't support this function."

    defp dispatch(payload, meta, %State{outstanding: outstanding} = state) do
      job = %{:erlang.binary_to_term(payload) | private: meta}
      {:noreply, [job], %{state | outstanding: outstanding - 1}}
    end

    defp ack(%PState{channel: channel}, %Job{private: %{delivery_tag: tag}}) do
      Basic.ack(channel, tag)
    end

    defp nack(queue, %Job{private: meta}) do
      nack(queue, meta)
    end

    defp nack(%PState{channel: channel}, %{delivery_tag: tag}) do
      Basic.reject(channel, tag, redeliver: true)
    end

    defp reserve_or_subscribe(queue, num), do: do_reserve_or_subscribe([], queue, num)

    defp do_reserve_or_subscribe(jobs, queue, 0), do: {queue, jobs}

    defp do_reserve_or_subscribe(jobs, %PState{channel: channel, name: name} = queue, num) do
      case Basic.get(channel, name) do
        {:empty, _meta} ->
          {:ok, consumer_tag} = Basic.consume(channel, name)
          {%{queue | consumer_tag: consumer_tag}, jobs}
        {:ok, payload, meta} ->
          job = %{:erlang.binary_to_term(payload) | private: meta}
          do_reserve_or_subscribe([job | jobs], queue, num - 1)
      end
    end
  end
end
