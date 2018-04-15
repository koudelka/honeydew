defmodule Honeydew.EctoSource.State do
  defstruct [
    :schema,
    :repo,
    :table,
    :key_field,
    :lock_field,
    :private_field,
    :stale_timeout,
    :queue
  ]

  @type stale_timeout :: pos_integer

  @type t :: %__MODULE__{schema: module,
                         repo: module,
                         table: String.t(),
                         key_field: String.t(),
                         lock_field: String.t(),
                         private_field: String.t(),
                         stale_timeout: stale_timeout,
                         queue: Honeydew.queue_name()}
end
