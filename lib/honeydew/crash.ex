defmodule Honeydew.Crash do
  @moduledoc false

  @type type :: :exception | :throw | :bad_return_value | :exit

  @type t :: %__MODULE__{
    type: type,
    reason: term,
    stacktrace: Exception.stacktrace()
  }

  defstruct [:type, :reason, :stacktrace]

  def new(type, reason, stacktrace)
  def new(:exception, %{__struct__: _} = exception, stacktrace) when is_list(stacktrace) do
    %__MODULE__{type: :exception, reason: exception, stacktrace: stacktrace}
  end

  def new(:throw, reason, stacktrace) when is_list(stacktrace) do
    %__MODULE__{type: :throw, reason: reason, stacktrace: stacktrace}
  end

  def new(:bad_return_value, value) do
    %__MODULE__{type: :bad_return_value, reason: value, stacktrace: []}
  end

  def new(:exit, reason) do
    %__MODULE__{type: :exit, reason: reason, stacktrace: []}
  end
end
