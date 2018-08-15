defmodule Honeydew.EctoPollQueueTest do
  use ExUnit.Case, async: true
  alias Honeydew.EctoPollQueue

  defmodule PseudoRepo do
    def __adapter__ do
      Ecto.Adapters.Postgres
    end
  end

  defmodule UnsupportedRepo do
    def __adapter__ do
      Ecto.Adapters.ButtDB
    end
  end

  defmodule PseudoSchema do
  end

  describe "rewrite_opts!/1" do
    test "should raise when :database isn't supported" do
      assert_raise ArgumentError, ~r/repo's ecto adapter/, fn ->
        queue = :erlang.unique_integer
        EctoPollQueue.rewrite_opts([queue, EctoPollQueue, [repo: UnsupportedRepo]])
      end
    end
  end

  describe "vaildate_args!/1" do
    test "shouldn't raise with valid args" do
      :ok = EctoPollQueue.validate_args!([repo: PseudoRepo, schema: PseudoSchema, poll_interval: 1, stale_timeout: 1])
    end

    test "should raise when poll interval isn't an integer" do
      assert_raise ArgumentError, ~r/Poll interval must/, fn ->
        EctoPollQueue.validate_args!([repo: PseudoRepo, schema: PseudoSchema, poll_interval: 0.5])
      end
    end

    test "should raise when stale timeout isn't an integer" do
      assert_raise ArgumentError, ~r/Stale timeout must/, fn ->
        EctoPollQueue.validate_args!([repo: PseudoRepo, schema: PseudoSchema, stale_timeout: 0.5])
      end
    end

    test "should raise when :repo or :schema arguments aren't provided" do
      assert_raise ArgumentError, ~r/didn't provide a required argument/, fn ->
        EctoPollQueue.validate_args!([repo: PseudoRepo])
      end

      assert_raise ArgumentError, ~r/didn't provide a required argument/, fn ->
        EctoPollQueue.validate_args!([schema: PseudoSchema])
      end
    end

    test "should raise when :repo or :schema arguments aren't loaded modules" do
      assert_raise ArgumentError, ~r/module you provided/, fn ->
        EctoPollQueue.validate_args!([repo: :abc, schema: PseudoSchema])
      end

      assert_raise ArgumentError, ~r/module you provided/, fn ->
        EctoPollQueue.validate_args!([repo: PseudoRepo, schema: :abc])
      end
    end

  end

end
