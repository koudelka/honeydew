# Caveats
- Honeydew attempts to provide "at least once" job execution, it's possible that circumstances could conspire to execute a job, and prevent Honeydew from reporting that success back to the queue. I encourage you to write your jobs idempotently.

- Honeydew isn't intended as a simple resource pool, the user's code isn't executed in the requesting process. Though you may use it as such, there are likely other alternatives that would fit your situation better, perhaps try [sbroker](https://github.com/fishcakez/sbroker).

- It's important that you choose a queue implementation to match your needs, see the [Queues section](https://github.com/koudelka/honeydew/blob/master/README/queues.md).
