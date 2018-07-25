defmodule TestSuccessMode do
  @behaviour Honeydew.SuccessMode

  @impl true
  def validate_args!(to: to) when is_pid(to), do: :ok

  @impl true
  def handle_success(job, [to: to]) do
    send to, job
  end
end

defmodule Helper do
  def restart_honeydew(_context) do
    :ok = Application.stop(:honeydew)
    :ok = Application.start(:honeydew)
  end
end

defmodule Tree do
  def tree(supervisor) do
    supervisor
    |> do_tree(0)
    |> List.flatten
    |> Enum.join("\n")
    |> IO.puts
  end

  defp do_tree(supervisor, depth) do
    supervisor
    |> Supervisor.which_children
    |> Enum.map(fn
      {id, pid, :supervisor, module} ->
        str = String.duplicate(" ", depth) <> "|-" <> "#{inspect pid} #{inspect module} #{inspect id}"
      [str | do_tree(pid, depth+1)]
    {id, pid, :worker, module} ->
        String.duplicate(" ", depth) <> "|-" <> "#{inspect pid} #{inspect module} #{inspect id}"
    end)
  end
end

# defmodule BadInit do
#   def init(_) do
#     :bad
#   end
# end

# defmodule RaiseOnInit do
#   def init(_) do
#     raise "bad"
#   end
# end

# defmodule LinkDiesOnInit do
#   def init(_) do
#     spawn_link fn -> :born_to_die end
#   end
# end

Honeydew.Support.Cluster.init()

ExUnit.start()
