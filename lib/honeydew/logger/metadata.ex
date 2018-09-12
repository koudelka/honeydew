defmodule Honeydew.Logger.Metadata do
  @moduledoc false

  alias Honeydew.Crash

  def build_crash_reason(%Crash{type: :exception, reason: exception, stacktrace: stacktrace}) do
    {exception, stacktrace}
  end

  def build_crash_reason(%Crash{type: :throw, reason: thrown, stacktrace: stacktrace}) do
    {{:nocatch, thrown}, stacktrace}
  end

  def build_crash_reason(%Crash{type: :bad_return_value, reason: value, stacktrace: stacktrace}) do
    {{:bad_return_value, value}, stacktrace}
  end
end
