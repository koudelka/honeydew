defmodule Honeydew.SuccessMode do
  @moduledoc """
  Behaviour module for implementing a job success mode.

  Honeydew comes with the following built-in failure modes:

  * `Honeydew.SuccessMode.Log`
  """
  alias Honeydew.Job

  @callback validate_args!(args :: list) :: any
  @callback handle_success(job :: %Job{}, args :: list) :: any
end
