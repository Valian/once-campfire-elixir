# Campfire on Phoenix

An idiomatic Elixir/Phoenix implementation of [ONCE Campfire](https://github.com/basecamp/once-campfire),
written from a spec rather than translated from the Rails source.

The [official Elixir port](https://github.com/basecamp/once-campfire-elixir) shown in the
[Campfire benchmark table](https://github.com/basecamp/once-campfire#readme) reproduces the
Rails app's structure in Elixir. Every query goes through a single GenServer, and Redis sits on
the hot path. Rack and Resque are emulated, and JSON is re-encoded for every subscriber.
Those numbers say more about the porting strategy than about Elixir. This repo asks
a different question: what do you get if you build the same app the way a Phoenix developer
normally would?

It is wire-compatible with the official benchmark harness. It uses the same SQLite database and
seed, the same HTML/DOM contract (Rails' compiled Turbo + Stimulus frontend is served unchanged)
and the same Action Cable protocol on `/cable`. As a result, the unchanged load generator runs
every suite against it.

## Design

| Concern | Approach |
|---|---|
| Web | Phoenix 1.8 controllers + HEEx function components on Bandit (no LiveView: the frontend is Rails' Turbo/Stimulus) |
| Database | Ecto on the Rails SQLite schema, WAL. One writer connection (`Campfire.Repo`, all writes serialized) plus a read-only pool with one connection per scheduler (`Campfire.Repo.Replica`) |
| Rendering | Message partials rendered once into an ETS fragment cache, with holes for the per-request CSRF token and host. Pages are iodata stitched from cached fragments |
| Real time | One WebSock process per connection speaking `actioncable-v1-json`. Fan-out uses local `Phoenix.PubSub`. Each payload is encoded **once** per broadcast, and each subscription only prepends its pre-encoded identifier |
| Rich text | Action Text HTML parsed once with LazyHTML. Sanitized and presented with checks against a 658-case Rails-rendered corpus |
| Files | Active Storage-compatible blobs and variants on disk. Thumbnails come from libvips via Vix |
| Ops | A single OTP release with no Redis, job queue or reverse proxy, and no distribution |

`docs/SPEC.md` is the implementation spec, derived from the Rails app and the benchmark
contract. `docs/ARCHITECTURE.md` maps the modules.

### Scope

Covered: everything the benchmark touches, plus core chat. That means sign-in, open/closed/direct
rooms, memberships and involvement, messages with rich text, mentions and attachments, edits,
deletes, boosts, unread tracking, the sidebar, search (FTS5), avatars, profile, presence and
typing indicators.

Not covered: web push delivery (subscriptions are stored but nothing is sent), bots/webhooks,
link unfurling, first-run/join codes/account admin, custom styles, and session transfers.

## Running it

```sh
docker build -t campfire-phoenix:app .
docker run -d -p 8080:80 \
  -e SECRET_KEY_BASE=$(openssl rand -hex 64) -e DISABLE_SSL=true \
  -v campfire:/rails/storage \
  campfire-phoenix:app
```

The database lives at `/rails/storage/db/production.sqlite3` and files under `/rails/storage/files`,
the same layout as Rails Campfire. An existing Campfire volume (and its `SECRET_KEY_BASE`)
works as-is. An empty database is initialised from `priv/repo/structure.sql`.

Development:

```sh
mix setup
SEED_DIR=bench/seed mix test     # tests run against a copy of the benchmark seed
mix phx.server
```

`bin/extract-assets` refreshes `priv/static` from the Rails reference image (`bench/make-seed`
builds it).

## Benchmarks

`bench/` holds two harnesses over the same Rust load generator, seed builder and suites from
[once-campfire-rust](https://github.com/basecamp/once-campfire-rust). Each app runs on a fresh
copy of the same seed with the same suites:

- HTTP: room page, messages page, sidebar, search, avatar, static CSS, `/up` and posting a
  message, each at 1/16/64 clients.
- Action Cable fan-out to 100/500/1,000 clients.
- Upload until the thumbnail is ready.

`bench/run-native` runs the apps as bare processes on Linux, pinned with taskset; the results
below come from it. `bench/run` is the macOS/Docker Desktop adaptation. Details and every knob are
in [`bench/README.md`](bench/README.md); the performance log is [`bench/PERF.md`](bench/PERF.md).

### Running the benchmarks

**1. Seed (once).** `bench/make-seed` needs Docker. It builds the Rails reference image and writes
`bench/seed/{db,storage,labels.json}`. The seed is deterministic, so on a machine without Docker
you can copy `bench/seed` from one that has it.

**2. Native Linux (the numbers below).**

You need:

- [mise](https://mise.jdx.dev). `bench/setup-native` uses it to get Rust, the reference's Ruby,
  and Erlang 28.5 + Elixir 1.19.5.
- These apt packages: `build-essential pkg-config libssl-dev libyaml-dev libsqlite3-dev
  libvips-dev libjemalloc2 ffmpeg`.
- Redis for Rails and the official port (not for this app), at `REDIS_URL` (default
  `redis://127.0.0.1:6379/0`), e.g. `docker run -d -p 127.0.0.1:6379:6379 redis:7`.
- 12 hardware threads for the default pinning: app on CPUs 4–7, load generator on 8–11, harness
  on 0–3. Change it with `SERVER_CPUS`, `LOADGEN_CPUS` and `HARNESS_CPUS`.

```sh
bench/setup-native                                   # build loadgen, Rails, the official port and this app
bench/run-native --apps reference,elixir-official,ours --reps 2                    # everything, ~30 min
bench/run-native --apps ours --reps 2                                              # this app only, ~10 min
HTTP_SECS=3 HTTP_CONCS=16 CABLE_CLIENTS=100 bench/run-native --apps ours --reps 1  # smoke test, ~2 min
bench/report bench/results/linux-<stamp>             # re-render report.md
```

`run-native` benchmarks the release in `_build/prod/rel/campfire`, so rebuild it after changing
code (`MIX_ENV=prod mix release --overwrite`, or `bench/setup-native ours`). Each run writes
`bench/results/linux-<stamp>/` containing:

- `report.md`: the tables;
- `env.txt`: host, commits, pinning, the scheduler counts each VM reports, and the observed
  process tree per run;
- `<app>-<rep>.json`: raw results;
- `run.log`: the harness log.

The tables below were made with `HTTP_SECS=5` (the default is 8) and the default concurrencies
and cable sizes. Before each app run, the harness waits for the 1-minute load average to drop
below `LOAD_MAX` (3) and records it.

**3. macOS / Docker Desktop.**

```sh
docker build -t campfire-phoenix:app . && bench/build-elixir-official
bench/run --apps reference,elixir-official,ours --reps 2
```

### Results: native Linux

Host: Intel i5-12500 (6 cores / 12 threads, 62 GB, Ubuntu 26.04, kernel 7.0, xfs on NVMe RAID1).
Each app is pinned with `taskset` to CPUs 4–7 (two physical cores and their hyperthreads) and the
load generator to 8–11, over loopback. 2 reps, 5 s per HTTP sample. Values are median requests/s,
with p99 latency in brackets. Zero non-2xx responses or errors in any sample.

The results come from two runs on the same host with the same harness and settings:

- This repo: [`linux-20261005-201440`](bench/results/linux-20261005-201440/report.md), at
  `065ec08`.
- Rails and the official port:
  [`linux-20261005-191554`](bench/results/linux-20261005-191554/report.md), an hour earlier,
  which ran all three apps in alternating order.

| Route, 16 clients | Rails | Official Elixir port | This repo |
|---|---:|---:|---:|
| Room page | 142 (250 ms) | 465 (45 ms) | **1,204 (19 ms)** |
| Messages page | 263 (120 ms) | 626 (37 ms) | **1,488 (16 ms)** |
| Sidebar | 350 (86 ms) | 779 (25 ms) | **2,391 (9 ms)** |
| Search | 266 (111 ms) | 796 (25 ms) | **1,763 (12 ms)** |
| Post a message | 165 (234 ms) | 487 (54 ms) | **970 (61 ms)** |
| Avatar ¹ | 50.3k | **51.5k** | 37.5k |
| Static CSS ¹ | 65.3k | 64.1k | **90.3k** |
| `/up` | 2.8k | 4.9k | **80.9k** |

| | Rails | Official Elixir port | This repo |
|---|---:|---:|---:|
| Room page, 1 client / 64 clients | 69 / 139 | 224 / 460 | **478 / 1,169** |
| Post a message, 1 client / 64 clients | 99 / 166 | 259 / 532 | **682 / 948** |
| Upload until thumbnail, median | 83 ms | 89 ms | **40 ms** |
| Cable, 1,000 clients: ready | 1,000 | 1,000 | 1,000 |
| Cable, 1,000 clients: post → all clients p50 / p99 | 134 / 185 ms | 34 / 55 ms | **17 / 35 ms** |
| Cable, 1,000 clients: delivered msg/s | 9.2 | 46 | **98** |
| Cable, 100 clients: delivered msg/s | 59 | 232 | **580** |
| Memory, idle / peak (PSS) ² | 313 / 1,305 MB | **141** / 536 MB | 162 / **427** MB |
| Cold start to `/up` | 2.8 s | **0.57 s** | 0.62 s |

¹ For Rails and the official port these are answered by Thruster's in-memory HTTP cache (all but
a handful of the ~600k requests per sample were cache hits), not by the app. Ours serves them
itself: avatars from an ETS cache through a minimal pipeline, CSS from `:persistent_term`.
² Sum over the app's processes (Puma + resque + Thruster, BEAM + Thruster, BEAM). Redis, which
the other two need, is external here and not included (18 MB and 37 MB RSS at the end of a run).

How it was run:

- **Commits.** This repo is at `065ec08` (branch `server-results`). Rails
  [once-campfire](https://github.com/basecamp/once-campfire) is at `90b3300`. The official port
  [once-campfire-elixir](https://github.com/basecamp/once-campfire-elixir) is at `b6b82e5`.
  Toolchain: Ruby 3.4.10 + jemalloc; OTP 28.5 (ERTS 16.4) and Elixir 1.19.5 for both Elixir
  apps; libvips 8.18.
- **Process models.** Each app runs as its image or Procfile does, with Redis moved out:
  - Rails: Thruster → Puma with 3 workers × 5 threads (`WEB_CONCURRENCY = ceil(0.666 × 4)`), plus
    resque-pool with 2 workers (its `resque-pool.yml`: `ceil(0.5 × 4)`).
  - Official port: Thruster → one BEAM, as in its `bin/container-start`.
  - This repo: one BEAM serving HTTP itself.
  - Both BEAMs get explicit `+S 4:4 +SDcpu 4:4` and report `schedulers_online=4`,
    `dirty_cpu_schedulers_online=4` and 10 dirty IO schedulers (`env.txt` has the observed
    process tree for every run).
- **Deviations from the Docker images.**
  - Redis is one shared external container on 127.0.0.1, `FLUSHALL`ed before each run, instead
    of running inside each app's container.
  - Thruster comes from the Rails bundle for both apps that use it, and logs every request as in
    the images.
  - The official port links the system SQLite (`EXQLITE_USE_SYSTEM=1`, as its Dockerfile does).
    Ours uses exqlite's bundled build.
  - The CPU governor is the host's `powersave`: intel_pstate with hardware P-states, EPP
    `balance_performance`, turbo on. Under load the pinned cores ran at 3.9–4.05 GHz on average,
    i.e. all-core turbo, so it isn't throttling throughput; `performance` would mainly help
    1-client latency. Changing it needs root, which the benchmark user doesn't have.
- **Host.** The machine is shared: the 1-minute load average was 2.6–3.0 at the start of each
  run (the harness waits for it to drop below 3).
- **This repo's earlier run.** Between `51c78be` (the three-app run) and `065ec08`, preloads
  were trimmed to the columns the partials render and avatars got a session-less pipeline.
  At 16 clients that moved the room page from 1,087 to 1,204, messages from 1,314 to 1,488, the
  sidebar from 1,881 to 2,391, search from 1,609 to 1,763 and avatars from 32k to 38k. Posting
  is unchanged (it's bound by the single writer).

The performance work behind these numbers (gzip level, scheduler busy-wait, WAL checkpoints,
in-memory assets), each change with its before and after, is in [`bench/PERF.md`](bench/PERF.md).

### Results: macOS / Docker Desktop (earlier)

Run `bench/results/20261005-154824`, before the performance pass: Apple M1 Pro, Docker Desktop,
each app limited to `--cpus 4`, 2 reps, 5 s per HTTP sample.

| Route, 16 clients | Rails | Official Elixir port | This repo |
|---|---:|---:|---:|
| Room page | 130 (323 ms) | 582 (39 ms) | **935 (35 ms)** |
| Messages page | 161 (720 ms) | 761 (35 ms) | **1,152 (35 ms)** |
| Sidebar | 328 (154 ms) | 771 (33 ms) | **1,728 (13 ms)** |
| Search | 244 (127 ms) | 841 (29 ms) | **1,400 (28 ms)** |
| Post a message | 147 (369 ms) | **315 (70 ms)** | 279 (82 ms) |
| Avatar | 13.4k | 14.0k | **15.6k** |
| Static CSS | 15.8k | **16.0k** | 11.4k |
| `/up` | 1.9k | 5.4k | **18.3k** |

| | Rails | Official Elixir port | This repo |
|---|---:|---:|---:|
| Upload until thumbnail, median | 214 ms | 173 ms | **87 ms** |
| Cable, 1,000 clients: post → all clients p99 | 626 ms | 130 ms | **93 ms** |
| Idle / peak memory | 374 / 1,914 MB | 182 / 601 MB | 178 / 693 MB |
| Cold start | 4.2 s | 1.4 s | 1.5 s |

That run went through Docker Desktop's port forwarder, which caps the cheap routes and caused
a few cable connection resets at 500–1,000 clients (these don't reproduce natively). Messages
were posted to a database on a virtiofs bind mount, where every write is slow. Compare its
figures with each other, not with the Linux table above.

## Credits and licence

Campfire is © 37signals, LLC, released under the MIT licence. This repo ships its compiled
frontend assets (`priv/static`) and, under `bench/`, the load generator, seed builder and
fixtures from 37signals' repositories, unmodified (see [`bench/NOTICE`](bench/NOTICE)). The Elixir code is
MIT licensed too; see [`LICENSE`](LICENSE).
