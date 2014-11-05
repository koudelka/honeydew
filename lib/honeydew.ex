defmodule Honeydew do
  use Application

  def start(_type, _args) do
    import Supervisor.Spec

    children = [
      supervisor(Honeydew.HomeSupervisor, [])
    ]

    opts = [strategy: :simple_one_for_one, name: Honeydew.Supervisor]

    Supervisor.start_link(children, opts)
  end


  def start_pool(honey_module, honey_init_args, opts) do
    # make sure the module exists
    try do
      apply(honey_module, :__info__, [:attributes])
    rescue UndefinedFunctionError ->
      raise ~s(Honeydew can't find the worker module named "#{honey_module}")
    end

    # start a HomeSupervisor
    Supervisor.start_child(Honeydew.Supervisor, [honey_module, honey_init_args, opts])
  end


  #
  # Process names
  #

  @doc "The process name for the HomeSupervisor of the given honey module."
  def home_supervisor(honey_module) do
    Honeydew
    |> Module.concat(honey_module)
    |> Module.concat(HomeSupervisor)
  end

  @doc "The process name for the JobList server of the given honey module."
  def job_list(honey_module) do
    Honeydew
    |> Module.concat(honey_module)
    |> Module.concat(JobList)
  end

  @doc "The process name for the HoneySupervisor of the given honey module."
  def honey_supervisor(honey_module) do
    Honeydew
    |> Module.concat(honey_module)
    |> Module.concat(HoneySupervisor)
  end


  defmacro __using__(_env) do
    quote do
      use Honeydew.Honey
    end
  end
end
