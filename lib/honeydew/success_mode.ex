defmodule Honeydew.SuccessMode do
  alias Honeydew.Job

  @callback handle_success(job :: %Job{}, args :: list) :: any
end
