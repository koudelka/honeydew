use Mix.Config

config :logger, :console,
  level: :info

config :riak_core,
  handoff_ip: '127.0.0.1',
  schema_dirs: ['priv'],
  node: 'dev@127.0.0.1',
  web_port: 8198,
  handoff_port: 8199,
  ring_state_dir: 'var/ring_data_dir_dev',
  platform_data_dir: 'var/data_dev',
  queue: Honeydew.Disorder
