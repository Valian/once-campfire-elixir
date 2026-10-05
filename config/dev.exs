import Config

# The bench secret, so the dev server can open a copy of bench/seed and verify its avatar tokens.
secret_key_base =
  "5335c3b1ad35b4ad170c3413bd651ef3b6ed64e257261871a6de3f978cf3868ee417a927040935fb30b0f7debdedb34a2a403e9f34b16cf594c917c2ecd4a995"

config :campfire, :secret_key_base, secret_key_base

config :campfire, CampfireWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT", "4000"))],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: secret_key_base,
  watchers: [],
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"lib/campfire_web/(controllers|components)/.*\.(ex|heex)$",
      ~r"lib/campfire_web/router\.ex$"
    ]
  ]

config :campfire, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

# No debug annotations: dev markup stays identical to prod (the loadgen regexes are exact).
