## 1.3.0 (2019-2-13)

### Enhancements
* Ecto 3 support

## 1.2.7 (2019-1-8)

### Enhancements
* Adding table prefixes to Ecto Poll Queue (thanks @jfornoff!)

## 1.2.6 (2018-9-19)

### Enhancements
* Honeydew crash log statements now include the following metadata
  `:honeydew_crash_reason` and `:honeydew_job`. These metadata entries
  can be used for building a LoggerBackend that could forward failures
  to an error logger integration like Honeybadger or Bugsnag.

## 1.2.5 (2018-8-24)

### Bug fixes
* Don't restart workers when linked process terminates normally

## 1.2.4 (2018-8-23)

### Bug fixes
* Catch thrown signals on user's init/1

## 1.2.3 (2018-8-23)

### Bug fixes
* Gracefully restart workers when an unhandled message is received.

## 1.2.2 (2018-8-23)

### Bug fixes
* Catch thrown signals from user's job code

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
