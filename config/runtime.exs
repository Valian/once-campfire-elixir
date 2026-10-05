import Config

if System.get_env("PHX_SERVER") do
  config :campfire, CampfireWeb.Endpoint, server: true
end

if config_env() != :test do
  config :campfire,
    app_version: System.get_env("APP_VERSION", "dev"),
    git_revision: System.get_env("GIT_REVISION", "dev"),
    vapid_public_key: System.get_env("VAPID_PUBLIC_KEY")

  database =
    System.get_env("DATABASE_PATH") ||
      if config_env() == :prod,
        do: "/rails/storage/db/production.sqlite3",
        else: Path.expand("../tmp/dev.sqlite3", __DIR__)

  config :campfire, Campfire.Repo, database: database
  # One reader per scheduler (OTP sizes schedulers from the container's CPU quota).
  config :campfire, Campfire.Repo.Replica,
    database: database,
    pool_size: System.schedulers_online()

  config :campfire,
         :storage_root,
         System.get_env("STORAGE_PATH") ||
           if(config_env() == :prod,
             do: "/rails/storage/files",
             else: Path.expand("../tmp/storage", __DIR__)
           )
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") || raise "environment variable SECRET_KEY_BASE is missing"

  config :campfire, :secret_key_base, secret_key_base

  # HTTP_PORT is what cf-rust's Linux harness passes; bench/run publishes container port 80.
  port = String.to_integer(System.get_env("HTTP_PORT") || System.get_env("PORT") || "80")

  config :campfire, CampfireWeb.Endpoint,
    server: true,
    http: [ip: {0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base
end
