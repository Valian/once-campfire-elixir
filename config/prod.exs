import Config

# No per-request logging: Phoenix.Logger stays detached and the level is warn.
config :phoenix, :logger, false
config :logger, level: :warning
