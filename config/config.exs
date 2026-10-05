import Config

config :campfire,
  ecto_repos: [Campfire.Repo],
  app_version: "dev",
  git_revision: "dev"

config :campfire, CampfireWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [formats: [html: CampfireWeb.ErrorHTML], layout: false],
  pubsub_server: Campfire.PubSub

# SQLite: one writer connection (Campfire.Repo) serializes all writes; a pool of read-only
# connections (Campfire.Repo.Replica) serves reads in parallel under WAL. Page cache is small
# per connection; mmap lets readers share the OS page cache instead.
sqlite_pragmas = [
  busy_timeout: 5000,
  synchronous: :normal,
  foreign_keys: :on,
  temp_store: :memory,
  cache_size: -8000,
  custom_pragmas: [mmap_size: 134_217_728]
]

config :campfire,
       Campfire.Repo,
       sqlite_pragmas ++
         [
           pool_size: 1,
           journal_mode: :wal,
           journal_size_limit: 67_108_864,
           default_transaction_mode: :immediate
         ]

config :campfire,
       Campfire.Repo.Replica,
       sqlite_pragmas ++ [mode: :readonly]

config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
