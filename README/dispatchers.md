# Dispatchers
Honeydew provides the following dispatchers:

- [LRUNode](https://hexdocs.pm/honeydew/Honeydew.Dispatcher.LRUNode.html) - Least Recently Used Node (sends jobs to the least recently used worker on the least recently used node, the default for global queues)
- [LRU](https://hexdocs.pm/honeydew/Honeydew.Dispatcher.LRU.html) - Least Recently Used Worker (FIFO, the default for local queues)
- [MRU](https://hexdocs.pm/honeydew/Honeydew.Dispatcher.MRU.html) - Most Recently Used Worker (LIFO)

You can also use your own dispatching strategy by passing it to `Honeydew.start_queue/2`. Check out the [built-in dispatchers](https://github.com/koudelka/honeydew/tree/master/lib/honeydew/dispatcher) for reference.
