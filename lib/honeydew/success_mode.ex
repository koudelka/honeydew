defmodule Honeydew.SuccessMode do
  alias Honeydew.Job

  @callback validate_args!(args :: list) :: any
  @callback handle_success(job :: %Job{}, args :: list) :: any
end
