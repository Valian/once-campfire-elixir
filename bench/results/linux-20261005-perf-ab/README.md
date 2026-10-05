# Native A/B runs behind bench/PERF.md (part 1)

`bench/run-native --apps ours --reps 1` with `SUITES=http HTTP_SECS=5 HTTP_CONCS="1 16 64"`, one
directory per run (`<variant>-<n>`, runs of a batch alternate). Each holds `ours-1.json` and `env.txt`.

| variant | build |
|---|---|
| `default`, `dirtyoff`, `alloff` | `perf-wip` + harness merge (2a091b3), `ELIXIR_ERL_OPTIONS` adding nothing / `+sbwtdcpu none +sbwtdio none` / also `+sbwt none` (PERF N2) |
| `final` | the shipped build (gzip 3, AssetCache, dirty busy-wait off, checkpoint every 4000 pages) |
| `nogzip` | `final` without `CampfireWeb.Gzip` (Bandit gzip level 6) (PERF N3) |
| `noasset` | `final` without `CampfireWeb.AssetCache` (Plug.Static) (PERF N4) |
| `ckpt1000` | `final` with the default WAL autocheckpoint (PERF N1) |
| `exq-ctrl`, `exq` | `final` with exqlite 0.42 built from source, unpatched / with `changes`, `columns`, `last_insert_rowid`, `transaction_status`, `release` as regular NIFs (experiment, PERF N1) |
