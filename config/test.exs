import Config

# Signing vectors in docs/SPEC.md and bench/seed/labels.json are made with the bench secret.
secret_key_base =
  "5335c3b1ad35b4ad170c3413bd651ef3b6ed64e257261871a6de3f978cf3868ee417a927040935fb30b0f7debdedb34a2a403e9f34b16cf594c917c2ecd4a995"

config :campfire, :secret_key_base, secret_key_base

# test_helper.exs copies bench/seed's DB here. Reads go through the write repo so they see
# sandboxed writes (Campfire.Repo.Replica isn't started in test).
config :campfire, Campfire.Repo,
  database: Path.expand("../tmp/test.sqlite3", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 1

config :campfire, Campfire.Repo.Replica, default_dynamic_repo: Campfire.Repo

config :campfire, CampfireWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: secret_key_base,
  server: false

config :campfire, :login_rate_limit, 1000

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

# bcrypt hashes in the seed are cost 12; new ones in tests needn't be.
config :bcrypt_elixir, :log_rounds, 4
