## 1.2.1 (2018-8-20)

### Bug fixes
* Stop ignoring `init_retry_secs` worker option
* Fixed `Honeydew.worker_opts` typespecs.
* Fixed `Honeydew.start_workers` specs.

## 1.2.0 (2018-8-17)

Honeydew now supervises your queues and workers for you, you no longer need to
add them to your supervision trees.

### Breaking Changes
* `Honeydew.queue_spec/2` and `Honeydew.worker_spec/3` are now hard deprecated
  in favor of `Honeydew.start_queue/2` and `Honeydew.start_workers/3`

### Bug fixes
* Rapidly failing jobs no longer have a chance to take down the worker supervisor.

### Enhancements
* `Honeydew.queues/0` and `Honeydew.workers/0` to list queues and workers running
  on the local node.
* `Honeydew.stop_queue/1` and `Honeydew.stop_workers/1` to stop local queues and
  workers
* Workers can now use the `failed_init/0` callback in combination with
  `Honeydew.reinitialize_worker` to re-init workers if their init fails.
* Many other things I'm forgetting...
  
## ?

### Breaking Changes

* Updated `Honeydew.cancel/1` to return `{:error, :not_found}` instead of `nil`
  when a job is not found on the queue. This makes it simpler to pattern match
  against error conditions, since the other condition is
  `{:error, :in_progress}`.
* Changed `Honeydew.Queue.cancel/2` callback to return `{:error, :not_found}`
  instead of `nil` when a job isn't found. This makes the return types the same
  as `Honeydew.cancel/1`.

### Bug fixes

* Fixed issue where new workers would process jobs from suspended queues (#35)

### Enhancements

* Docs and typespecs for the following functions
    * `Honeydew.async/3`
    * `Honeydew.filter/2`
    * `Honeydew.resume/1`
    * `Honeydew.suspend/1`
    * `Honeydew.yield/2`

## 1.0.4 (2017-11-29)

### Breaking Changes

* Removed `use Honeydew.Queue` in favor of `@behaviour Honeydew.Queue` callbacks

### Enhancements

* Added Honeydew.worker behaviour
* Relaxed typespec for `Honeydew.worker_spec/3` `module_and_args` param (#27)
* New docs for
    * `Honeydew.FailureMode`
    * `Honeydew.FailureMode.Abandon`
    * `Honeydew.FailureMode.Move`
    * `Honeydew.FailureMode.Retry`
    * `Honeydew.Queue.ErlangQueue`
    * `Honeydew.Queue.Mnesia`
* Validate arguments for success and failure modes
