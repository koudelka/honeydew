defmodule Honeydew.FailureMode do
  alias Honeydew.Job

  @callback handle_failure(job :: %Job{}, reason :: any, args :: list) :: any
end
