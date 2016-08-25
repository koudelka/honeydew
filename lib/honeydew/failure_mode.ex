defmodule Honeydew.FailureMode do
  alias Honeydew.Job

  @callback handle_failure(pool :: atom, job :: %Job{}, queue :: atom, args :: list) :: any
end
