# Job Lifecycle
In general, a job goes through the following stages:

```
|─ The user's process calls `async/3`, which packages the task tuple/fn up into a Job and sends it to a
|  member of the queue group.
|
├─ The queue process recieves the Job and enqueues it
|  ├─ If there is a Worker available, the queue will dispatch the Job immediately to the waiting Worker
|  |  via the selected dispatch strategy.
|  └─ If there aren't any Workers available, the Job will remain in the queue until a Worker announces
|     that it's ready.
|
├─ Upon dispatch, the queue "reserves" the Job (marks it as in-progress), then spawns a local JobMonitor
|  process to watch the Worker.
└─ The JobMonitor starts a timer, if the Worker doesn't claim the Job in time, the queue will assume
   there's a problem with the Worker and find another.
   ├─ When the Worker receives the Job, it informs the JobMonitor. The JobMonitor then watches the Worker
   |  in case it crashes (bug, cluster disconnect, etc).
   └─ The Worker spawns a JobRunner, providing it with the Job and the user's state from init/1.
      |
      ├─ If the Job crashes
      |  | ├─ And the error was trapable (rescue/catch), the JobRunner reports the issue to the Worker and
      |  | |  gracefully stops.
      |  | └─ If it caused the JobRunner to brutally terminate, the Worker takes note.
      |  ├─ The Worker informs the JobMonitor of the failure, the JobMonitor executes the selected
      |  |  FailureMode gracefully stops.
      |  └─ The Worker then executes a controlled restart, because it assumes something is wrong with the
      |     state the user provided (a dead db connection, for example).
      |
      └─ If the Job succeeds
         ├─ The JobRunner reports the success to the Worker along with the result, and gracefully stops.
         ├─ If the Job was enqueued with `reply: true`, the Worker sends the result to the user's process.
         ├─ The Worker sends an acknowledgement message to the JobMonitor.
         |  └─ The JobMonitor sends an acknowledgement to the queue to remove the Job, executes the
         |     selected SuccessMode and gracefully stops.
         └─ The Worker informs the queue that it's ready for a new Job. The queue checks the Worker in
            with the dispatcher and the cycle starts again.
```
