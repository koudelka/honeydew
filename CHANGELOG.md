## Unreleased

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
