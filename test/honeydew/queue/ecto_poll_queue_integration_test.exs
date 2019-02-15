defmodule Honeydew.EctoPollQueueIntegrationTest do
  alias Mix.Shell.IO, as: Output
  use ExUnit.Case, async: false
  @tag timeout: 2 * 60 * 1_000
  @examples_root "./examples/ecto_poll_queue"

  # Postgres
  test "ecto poll queue external project test: Postgres" do
    announce_test("Postgres (unprefixed)")
    :ok = mix("deps.get", "postgres", prefixed: false)
    :ok = mix("test", "postgres", prefixed: false)
  end

  test "ecto poll queue external project test: Postgres (prefixed)" do
    announce_test("Postgres (prefixed)")
    :ok = mix("deps.get", "postgres", prefixed: true)
    :ok = mix("test", "postgres", prefixed: true)
  end

  # Cockroach
  test "ecto poll queue external project test: Cockroach" do
    announce_test("CockroachDB (unprefixed)")
    :ok = mix("deps.get", "cockroach", prefixed: false)
    :ok = mix("test", "cockroach", prefixed: false)
  end

  defp announce_test(message) do
    Output.info(
      "\n#{IO.ANSI.underline()}[ECTO POLL QUEUE INTEGRATION] #{message}#{IO.ANSI.reset()}"
    )
  end

  defp mix(task, database, opts) when is_binary(task), do: mix([task], database, opts)

  defp mix(task, database, prefixed: prefixed_tables) do
    environment = [{"MIX_ENV", database}] |> add_prefixed_tables_env(prefixed_tables)

    {_, exit_code} =
      System.cmd("mix", task, cd: @examples_root, into: IO.stream(:stdio, 1), env: environment)

    if exit_code == 0 do
      :ok
    else
      {:error, exit_code}
    end
  end

  defp add_prefixed_tables_env(env, true), do: env ++ [{"prefixed_tables", "true"}]
  defp add_prefixed_tables_env(env, false), do: env
end
