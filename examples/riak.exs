defmodule Riak do
  @moduledoc """
    This is an example Worker to interface with Riak.
    You'll need to add the erlang riak driver to your mix.exs:
    `{:riakc, ">= 2.4.1}`
  """

  def init([ip, port]) do
    :riakc_pb_socket.start_link(ip, port) # returns {:ok, riak}
  end

  def up?(riak) do
    :riakc_pb_socket.ping(riak) == :pong
  end

  def put(bucket, key, obj, content_type, riak) do
    :ok = :riakc_pb_socket.put(riak, :riakc_obj.new(bucket, key, obj, content_type))
  end

  def get(bucket, key, riak) do
    case :riakc_pb_socket.get(riak, bucket, key) do
      {:ok, obj} -> :riakc_obj.get_value(obj)
      {:error, :notfound} -> nil
      error -> error
    end
  end
end

defmodule App do
  def start do
    children = [
      Honeydew.queue_spec(:riak),
      Honeydew.worker_spec(:riak, {Riak, ['127.0.0.1', 8087]}, num: 5, init_retry_secs: 10)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
