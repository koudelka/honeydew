defmodule Honeydew.EctoPollQueueIntegrationTest do
  use ExUnit.Case, async: false
  @tag timeout: 2 * 60 * 1_000
  @examples_root "./examples/ecto_poll_queue"

  File.cwd!
  |> Path.join(@examples_root)
  |> File.ls!
  |> Enum.filter(& [File.cwd!, @examples_root, &1] |> Path.join |> File.dir?)
  |> Enum.each(fn database ->
    test "ecto poll queue external project test: #{database}" do
      IO.puts("\n")
      IO.puts("------- Ecto Poll Queue: #{unquote(database)} -------")
      cd = Path.join(@examples_root, unquote(database))
      mix "deps.get", cd
      mix "test", cd
      IO.puts("-------------------------------")
    end
  end)


  defp mix(task, cd) do
    {_, exit_code} = System.cmd("mix", [task], cd: cd, into: IO.stream(:stdio, 1))
    assert exit_code == 0
  end

end
