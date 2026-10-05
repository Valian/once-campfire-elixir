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

`bench/` holds a macOS/Docker Desktop adaptation of the harness from
[once-campfire-rust](https://github.com/basecamp/once-campfire-rust): the same Rust load
generator, seed builder and environment. It runs every app on a fresh copy of the same seed, with
the same suites. See [`bench/README.md`](bench/README.md).

```sh
bench/make-seed                 # builds the Rails reference image and the seed
bench/build-elixir-official     # optional: the official Elixir port, for comparison
bench/run --apps reference,elixir-official,ours --reps 2
```

### Results so far

Run `bench/results/20261005-154824`: Apple M1 Pro, Docker Desktop, each app limited to
`--cpus 4`, 2 reps, 5 s per HTTP sample. Values are requests/s with p99 latency in brackets.

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

These numbers are **work in progress**. A profiling pass is underway on three known weak spots:
gzip cost on the ~460 KB room page, writer occupancy when posting, and static asset serving.
Also, a few cable clients get connection resets at 500–1,000 clients behind Docker Desktop's
port forwarder.

Caveats: this is a laptop in Docker Desktop, with other containers running in the same VM.
Throughput on the cheap routes is bounded by Docker's port forwarder. The figures are comparable
with each other, **not** with the Linux numbers in the upstream README.

## Credits and licence

Campfire is © 37signals, LLC, released under the MIT licence. This repo ships its compiled
frontend assets (`priv/static`) and, under `bench/`, the load generator, seed builder and
fixtures from 37signals' repositories, unmodified (see [`bench/NOTICE`](bench/NOTICE)). The Elixir code is
MIT licensed too; see [`LICENSE`](LICENSE).
