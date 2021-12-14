# API

Please see the [Honeydew](https://hexdocs.pm/honeydew/Honeydew.html) module's hexdocs for Honeydew's complete API.

### Suspend and Resume
You can suspend a queue (halt the distribution of new jobs to workers), by calling [suspend/1](https://hexdocs.pm/honeydew/Honeydew.html#suspend/1), then resume with [resume/1](https://hexdocs.pm/honeydew/Honeydew.html#resume/1).

### Cancelling Jobs
To cancel a job that hasn't yet run, use [cancel/1|2](https://hexdocs.pm/honeydew/Honeydew.html#cancel/1).

See the included [example](https://github.com/koudelka/honeydew/blob/centralize/examples/filter_and_cancel.exs).

### Moving Jobs
You can move a job from one queue to another, if it hasn't been started yet, with [move/2](https://hexdocs.pm/honeydew/Honeydew.html#move/2).

### Listing Jobs
You can list (and optionally filter the list) of jobs in a queue with [filter/2](https://hexdocs.pm/honeydew/Honeydew.html#filter/2).

See the included [example](https://github.com/koudelka/honeydew/blob/centralize/examples/filter_and_cancel.exs).

### Job Progress
Your jobs can emit their current status, i.e. "downloaded 10/50 items", using the `progress/1` function given to your job module by `use Honeydew.Progress`.

See the included [example](https://github.com/koudelka/honeydew/blob/centralize/examples/progress_and_queue_status.exs).

### Job Replies
By passing `reply: true` to [async/3](https://hexdocs.pm/honeydew/Honeydew.html#async/3), you can receive replies from your jobs with [yield/2](https://hexdocs.pm/honeydew/Honeydew.html#yield/2).

See the included [example](https://github.com/koudelka/honeydew/blob/centralize/examples/job_replies.exs)
