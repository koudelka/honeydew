defmodule Honeydew.FailureMode do
  @moduledoc """
  Behaviour module for implementing a job failure mechanism in Honeydew.

  Honeydew comes with the following built-in failure modes:

  * `Honeydew.FailureMode.Abandon`
  * `Honeydew.FailureMode.Move`
  * `Honeydew.FailureMode.Retry`
  """
  alias Honeydew.Job

  @callback validate_args!(args :: list) :: any
  @callback handle_failure(job :: %Job{}, reason :: any, args :: list) :: any
end
