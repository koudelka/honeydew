defmodule Honeydew.GlobalTest do
  use ExUnit.Case, async: true
  alias Honeydew.Support.ClusterSetups

  setup [:setup_queue_name]

  describe "simple global queue" do

    setup %{queue: queue} do
      %{sup: _queue_sup} = ClusterSetups.start_queue_node(queue)
      %{sup: _worker_sup} = ClusterSetups.start_worker_node(queue)

      :ok
    end

    test "hammer async/3", %{queue: queue} do
      Enum.each(0..10_000, fn i ->
        {:send_msg, [self(), i]} |> Honeydew.async(queue)
        assert_receive ^i
      end)
    end

    test "yield/2", %{queue: queue} do
      first_job  = {:return, [:hi]} |> Honeydew.async(queue, reply: true)
      second_job = {:return, [:there]} |> Honeydew.async(queue, reply: true)

      assert {:ok, :hi}    = Honeydew.yield(first_job)
      assert {:ok, :there} = Honeydew.yield(second_job)
    end
  end

  defp setup_queue_name(_), do: {:ok, [queue: generate_queue_name()]}

  defp generate_queue_name do
    {:global, :crypto.strong_rand_bytes(10) |> Base.encode16}
  end
end
