defmodule Honeydew.EctoPollQueueIntegrationTest do
  use ExUnit.Case, async: false
  @tag timeout: 2 * 60 * 1_000

  test "ecto poll queue external project test" do
    IO.puts("\n")
    IO.puts("------- Ecto Poll Queue -------")
    mix "deps.get"
    mix "test"
    IO.puts("-------------------------------")
  end

  defp mix(task) do
    {_, exit_code} = System.cmd("mix", [task], cd: "./examples/ecto_poll_queue",
                                               into: IO.stream(:stdio, 1))
    assert exit_code == 0
  end
end
