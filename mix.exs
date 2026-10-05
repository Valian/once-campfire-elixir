defmodule Campfire.MixProject do
  use Mix.Project

  def project do
    [
      app: :campfire,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      releases: [campfire: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [
      mod: {Campfire.Application, []},
      extra_applications: [:logger, :runtime_tools, :crypto]
    ]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.9"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      # HEEx function components live here; we don't use LiveView itself.
      {:phoenix_live_view, "~> 1.2.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:bcrypt_elixir, "~> 3.3"},
      # libvips (precompiled): avatar variants.
      {:vix, "~> 0.42"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: [&copy_seed_db/1, "test"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end

  # Tests run against a copy of the benchmark seed (a real Rails database; `bench/make-seed`,
  # or SEED_DIR), copied before the app boots and opens it. The sandbox rolls back each test.
  defp copy_seed_db(_) do
    seed = Path.join(System.get_env("SEED_DIR", "bench/seed"), "db/production.sqlite3")

    File.exists?(seed) ||
      Mix.raise("no seed database at #{seed}: run bench/make-seed or set SEED_DIR")

    File.mkdir_p!("tmp")

    for suffix <- ["", "-wal"], File.exists?(seed <> suffix) do
      File.cp!(seed <> suffix, "tmp/test.sqlite3" <> suffix)
    end

    File.rm("tmp/test.sqlite3-shm")

    File.rm_rf!("tmp/test-storage")
    storage = Path.join(System.get_env("SEED_DIR", "bench/seed"), "storage")
    if File.dir?(storage), do: File.cp_r!(storage, "tmp/test-storage")
  end
end
