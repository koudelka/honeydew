defmodule Honeydew.Progress do
  defmacro __using__(_opts) do
    quote do
      def progress(update) do
        monitor = Process.get(:monitor)
        :ok = GenServer.call(monitor, {:progress, update})
      end
    end
  end
end
