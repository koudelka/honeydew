# Job Lifecycle
In general, a job goes through the following stages:

```
- The requesting process calls `async/3`, which packages the task tuple/fn up into a Job and sends
  it to a member of the queue group.

- The queue process will enqueue the job, then take one of the following actions:
  ├─ If there is a worker available, the queue will dispatch the job immediately to the waiting
  |  worker via the selected dispatch strategy.
  └─ If there aren't any workers available, the job will remain in the queue until a worker announces
     that it's ready.

- Upon dispatch, the queue "reserves" the job (marks it as in-progress), then spawns a local JobMonitor
  process to watch the worker.
- The monitor starts a timer after which the job will be returned to the queue. This is done to avoid
  blocking the queue while waiting for confirmation from the worker that it has received the job.
  └─ When the worker receives the job, it informs the monitor associated with the job. The monitor
     then watches the worker in case the job crashes.
     ├─ When the job succeeds:
     |  ├─ If the job was enqueued with `reply: true`, the result is sent.
     |  ├─ The worker sends an acknowledgement message to the monitor.
     |  |  |─ The monitor sends an acknowledgement to the queue to remove the job.
     |  |  └─ The monitor executes the selected success mode and terminates.
     |  └─ The worker informs the queue that it's ready for a new job. The queue checks the worker in with the
     |     dispatcher and the cycle starts again.
     └─ If the task crashes, the monitor executes the selected failure mode and terminates. The worker then
        executes a controlled restart .
```
