# This is your worker
defmodule CatFeedingHoney do
  use Honeydew

  def init(pantry_location) do
    Pantry.init(pantry_location)
  end

  # the last argument is always the honey's state
  def make_snack(kind, kitty, pantry) do
    snack = Pantry.get(pantry, :snacks, kind)
    "#{snack} snack for #{kitty}!"
  end

  def go_shopping(pantry) do
    Pantry.put(pantry, :snacks, :tuna)
    IO.puts("went shopping")
  end
end


# This is your database
defmodule Pantry do
  def init(_location) do
    {:ok, :pantry_connection}
  end

  def get(_pantry_connection, _shelf, item) do
    item
  end

  def put(_pantry_connection, _shelf, item) do
    item
  end
end

CatFeedingHoney.start_pool("kitchen")

#
# Blocking call
#
CatFeedingHoney.call(:make_snack, [:tuna, :darwin]) # -> "tuna snack for darwin!"

#
# Non-blocking cast
#
CatFeedingHoney.cast(:go_shopping) # -> prints "went shopping"

#
# You can pass arbitrary functions to be executed, too.
#
CatFeedingHoney.call(fn(pantry) -> IO.inspect pantry end) # -> :pantry_connection
