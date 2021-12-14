# Failure Modes
When a worker crashes, a monitoring process runs the `handle_failure/3` function from the selected module on the queue's node. Honeydew ships with two failure modes, at present:

- [Abandon](https://hexdocs.pm/honeydew/Honeydew.FailureMode.Abandon.html) - Simply forgets about the job.
- [Move](https://hexdocs.pm/honeydew/Honeydew.FailureMode.Move.html) - Removes the job from the original queue, and places it on another.
- [Retry](https://hexdocs.pm/honeydew/Honeydew.FailureMode.Retry.html) - Re-attempts the job on its original queue a number of times, then calls another failure mode after the final failure.

See [Honeydew.start_queue/3](https://hexdocs.pm/honeydew/Honeydew.html#start_queue/3) to select a failure mode.

# Success Modes
When a job completes successfully, the monitoring process runs the `handle_success/2` function from the selected module on the queue's node. You'll likely want to use this callback for monitoring purposes. You can use a job's `:enqueued_at`, `:started_at` and `:completed_at` fields to calculate various time intervals.

See [Honeydew.start_queue/3](https://hexdocs.pm/honeydew/Honeydew.html#start_queue/3) to select a success mode.
