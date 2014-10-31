defmodule Honeydew.RiakHoney do
  use Honeydew

  @moduledoc """
    This is an example Honey to interface with Riak. You'll need to add the erlang riak driver to your mix.exs' deps to use it `{:riakc, github: "basho/riak-erlang-client"}`
  """

  def init({ip, port}) do
    :riakc_pb_socket.start_link(ip, port)
  end

  def up?, do: call(:up?)
  def up?(riak) do
    :riakc_pb_socket.ping(riak) == :pong
  end

  def put(bucket, key, obj, content_type, riak) do
    :riakc_pb_socket.put(riak, :riakc_obj.new(bucket, key, obj, content_type))
  end

  def get(bucket, key), do: call(:get, [bucket, key])
  def get(bucket, key, riak) do
    case :riakc_pb_socket.get(riak, bucket, key) do
      {:ok, obj} -> :riakc_obj.get_value(obj)
      {:error, :notfound} -> nil
      error -> error
    end
  end
end
