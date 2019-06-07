## 1.4.2 (2019-6-7)

### Bug Fixes

* Don't ignore mnesia table options provided by the user. Thanks @X4lldux!

## 1.4.1 (2019-5-9)

### Enhancements

* Job execution filtering for Ecto Poll Queue with `:run_if` option, taking a boolean SQL fragment
* Adding `:timeout` option to `Honeydew.status/2`

## 1.4.0 (2019-4-8)

### Enhancements
* __Delayed Jobs__

  You may now pass the `:delay_secs` argument to `async/3` to execute a job when the given number of seconds has passed.

  See the [Delayed Job Example](https://github.com/koudelka/honeydew/blob/master/examples/delayed_job.exs)

  Queue Support:
    - `Mnesia`
  
    Fully supported, uses the system's montonic clock. It's recommended to use [Multi Time Warp Mode](http://erlang.org/doc/apps/erts/time_correction.html#multi-time-warp-mode), to prevent the monotonic clock from freezing for extended periods during a time correction, with `--erl "+C multi_time_warp"`.
    - `EctoPollQueue`
  
    Unsupported, since the Ecto queue doesn't use `async/3`. However, delayed retries are supported.
    
    It's technically feasible to delay Ecto jobs. As Honeydew wants nothing to do with your model's insertion transaction (to limit its impact on your application), its job ordering is handled by default values in the migration. In order to delay Ecto jobs, you'll need to manually add a number of milliseconds to the `DEFAULT` value of honeydew's lock field in your insertion transaction.
  
    - `ErlangQueue`
  
    Unsupported, pending a move to a priority queue. See "Breaking Changes" below to use delayed jobs with an in-memory queue.

* __Exponential Retry (backoff)__

  Honeydew now supports exponential retries with the `ExponentialRetry` failure mode. You can optionally set the
  exponential base with the `:base` option, the default is `2`.

  See the [Exponential Retry example](https://github.com/koudelka/honeydew/blob/master/examples/exponential_retry.exs) and [docs](https://hexdocs.pm/honeydew/1.4.0/Honeydew.FailureMode.ExponentialRetry.html)

* __Customizable Retry Strategies__

  The `Retry` failure mode is now far more customizable, you can provide your own function to determine if, and when, you want
  to retry the job (by returning either `{:cont, state, delay_secs}` or `:halt`).
  
  See the [Exponential Retry Implementation](https://github.com/koudelka/honeydew/blob/master/lib/honeydew/failure_mode/exponential_retry.ex) and [docs](https://hexdocs.pm/honeydew/1.4.0/Honeydew.FailureMode.Retry.html)


### Breaking Changes
* [Mnesia] The schema for the Mnesia queue has been simplified to allow for new features and
  future backward compatibility. Unfortuntaely, this change itself isn't backward compatible.
  You'll need to drain your queues and delete your on-disk mnesia schema files (`Mnesia.*`),
  if you're using `:on_disc`, before upgrading and restarting your queues.

* [Mnesia] The arguments for the Mnesia queue have been simplified, you no longer need to explicitly
  provide a separate list of nodes, simply provide the standard mnesia persistence arguments:
  `:ram_copies`, `:disc_copies` and `:disc_only_copies`.
  
  See the [Mnesia Example](https://github.com/koudelka/honeydew/blob/master/examples/mnesia.exs)

* [ErlangQueue] The in-memory ErlangQueue is no longer the default queue, since it doesn't currently
  support delayed jobs. If you still want to use it, you'll need to explicitly ask for it when starting
  your queue, with the `:queue` argument. Instead, the default queue is now an Mnesia queue using `:ram_copies`
  and the `:ets` access mode.

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
