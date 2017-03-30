defmodule Honeydew.NodeMonitor do
  use GenServer
  require Logger

  @interval 1_000 # ms

  def start_link(node) do
    GenServer.start_link(__MODULE__, node)
  end

  def init(node) do
    :ok = :net_kernel.monitor_nodes(true)

    GenServer.cast(self(), :ping)

    {:ok, node}
  end

  def handle_cast(:ping, node) do
    node
    |> Node.ping
    |> case do
         :pang -> :timer.apply_after(@interval, GenServer, :cast, [self(), :ping])
          _ -> :noop
       end
    {:noreply, node}
  end

  def handle_info({:nodeup, node}, node) do
    Logger.info "[Honeydew] Connection to #{node} established."

    {:noreply, node}
  end
  def handle_info({:nodeup, _}, node), do: {:noreply, node}

  def handle_info({:nodedown, node}, node) do
    Logger.warn "[Honeydew] Lost connection to #{node}, attempting to reestablish..."

    GenServer.cast(self(), :ping)

    {:noreply, node}
  end
  def handle_info({:nodedown, _}, node), do: {:noreply, node}

end
