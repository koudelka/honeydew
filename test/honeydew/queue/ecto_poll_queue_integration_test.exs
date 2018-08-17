defmodule Honeydew.EctoPollQueueIntegrationTest do
  use ExUnit.Case, async: false
  @tag timeout: 2 * 60 * 1_000
  @examples_root "./examples/ecto_poll_queue"
  @databases ~w(postgres cockroach)

  Enum.each(@databases, fn database ->
    test "ecto poll queue external project test: #{database}" do
      database = unquote(database)
      IO.puts("\n")
      IO.puts("------- Ecto Poll Queue: #{database} -------")
      mix "deps.get", database
      mix "test", database
      IO.puts("-------------------------------")
    end
  end)

  defp mix(task, database) do
    {_, exit_code} = System.cmd("mix", [task], cd: @examples_root, into: IO.stream(:stdio, 1), env: [{"MIX_ENV", database}])
    assert exit_code == 0
  end
end
