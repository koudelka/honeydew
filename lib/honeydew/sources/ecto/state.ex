defmodule Honeydew.EctoSource.State do
  @moduledoc false

  defstruct [
    :schema,
    :repo,
    :sql,
    :table,
    :key_fields,
    :lock_field,
    :private_field,
    :task_fn,
    :queue,
    :stale_timeout,
    :reset_stale_interval,
    :run_if
  ]

  @type stale_timeout :: pos_integer

  @type t :: %__MODULE__{schema: module,
                         repo: module,
                         sql: module,
                         table: String.t(),
                         key_fields: [atom()],
                         lock_field: String.t(),
                         private_field: String.t(),
                         stale_timeout: stale_timeout,
                         task_fn: function(),
                         queue: Honeydew.queue_name(),
                         reset_stale_interval: pos_integer(),
                         run_if: String.t()}
end
