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
  Go (the version in its `go.mod`), and Erlang 28.5 + Elixir 1.19.5.
- These apt packages: `build-essential pkg-config libssl-dev libyaml-dev libsqlite3-dev
  libvips-dev libjemalloc2 ffmpeg`.
- Redis for Rails and the official port (Go and this app do not use it), at `REDIS_URL` (default
  `redis://127.0.0.1:6379/0`), e.g. `docker run -d -p 127.0.0.1:6379:6379 redis:7`.
- 12 hardware threads for the default pinning: app on CPUs 4–7, load generator on 8–11, harness
  on 0–3. Change it with `SERVER_CPUS`, `LOADGEN_CPUS` and `HARNESS_CPUS`.

```sh
bench/setup-native                                   # build loadgen, Rails, official Elixir, Go and this app
bench/setup-native go                                # add Go to an existing native setup
HTTP_SECS=5 bench/run-native --apps reference,elixir-official,go,ours --reps 2       # everything
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
Each app is pinned with `taskset` to CPUs 4–7 (two physical cores and their hyperthreads), the
load generator to 8–11, and the harness to 0–3. All four apps ran sequentially on fresh copies
of the same seed, twice, with the order reversed for the second repetition. HTTP samples last
5 seconds at 1/16/64 clients after a 2-second warmup. Every timed HTTP request asks for gzip.

Full report and raw results: [`linux-20261005-205011-with-go`](bench/results/linux-20261005-205011-with-go/report.md).
The tables show medians across the two repetitions; the full report also shows their ranges.
HTTP values are requests/s with the median per-run p99 latency in brackets. All samples had
zero HTTP failures. Every successful HTTP post was persisted and indexed.

| Route, 16 clients | Rails | Official Elixir port | Go | This repo |
|---|---:|---:|---:|---:|
| Room page | 143 (268 ms) | 472 (45 ms) | **1,732 (38 ms)** | 1,210 (19 ms) |
| Messages page | 272 (128 ms) | 636 (37 ms) | **2,235 (25 ms)** | 1,481 (16 ms) |
| Sidebar | 369 (70 ms) | 794 (26 ms) | **8,378 (6 ms)** | 2,374 (9 ms) |
| Search | 272 (109 ms) | 767 (26 ms) | **3,078 (17 ms)** | 1,642 (13 ms) |
| Post a message | 166 (239 ms) | 462 (57 ms) | **1,482 (42 ms)** | 987 (61 ms) |
| Avatar ¹ | 51.7k | 53.0k | **102.5k** | 37.1k |
| Static CSS ¹ | 66.5k | 66.2k | **142.4k** | 89.8k |
| `/up` | 2,896 | 4,869 | 75.6k | **80.5k** |

At 16 clients, Go achieves 1.4–3.5× this repo’s throughput across the four read views and
1.5× for posting. At 1,000 Cable clients, Go delivers 159.2 complete broadcasts/s compared
with 99.5 for this repo. These throughput comparisons should be read alongside the p99
latencies and response-size differences below.

| | Rails | Official Elixir port | Go | This repo |
|---|---:|---:|---:|---:|
| Room page, 1 client / 64 clients | 71 / 134 | 229 / 469 | 692 / 1,721 | 489 / 1,182 |
| Post a message, 1 client / 64 clients | 107 / 163 | 265 / 498 | 749 / 1,481 | 712 / 953 |
| Upload until thumbnail, median | 69.8 ms | 88.2 ms | 38.6 ms | 41.2 ms |
| Cable, 1,000 clients: ready | 1,000 | 1,000 | 1,000 | 1,000 |
| Cable, 1,000 clients: post → all clients p50 / p99 | 130 / 245 ms | 27 / 61 ms | 14 / 42 ms | 15 / 54 ms |
| Cable, 1,000 clients: complete broadcasts/s | 9.4 | 47.0 | 159.2 | 99.5 |
| Cable, 100 clients: complete broadcasts/s | 60.3 | 237.6 | 697.6 | 585.6 |
| Memory, idle / peak (PSS) ² | 316 / 1336 MB | 146 / 552 MB | 31 / 301 MB | 159 / 436 MB |
| Cold start to `/up` | 2,689 ms | 564 ms | 54 ms | 598 ms |

¹ Rails and the official Elixir port serve these through Thruster’s in-memory HTTP cache.
Go uses its built-in public front end and cache. This repo serves avatars from ETS through a
minimal pipeline and CSS from `:persistent_term`.
² PSS is summed over each app’s process tree. Redis is external and excluded for the two apps
which use it; its RSS is recorded separately in the full report.

**Workload validation and response size.** Before timing, every app returned the same 40
room/history message IDs, 13 search result IDs, 9 sidebar room IDs, and identical avatar bytes.
Probes use the same encoding as the timed requests. Validation records and write/index counts
are in the result directory’s `validation/`. The HTML differs between implementations: Go’s
room HTML is about 20% smaller than this repo’s, and its sidebar HTML about 70% smaller.
Go’s higher read throughput also comes with higher room/history/search p99 latency than this
repo in these samples; see both throughput and latency in the table.

**Builds and process models.**

- Rails: [once-campfire](https://github.com/basecamp/once-campfire) at `90b3300`, Ruby 3.4.10
  with jemalloc; Thruster → Puma, 3 workers × 5 threads, plus 2 resque workers.
- Official Elixir: [once-campfire-elixir](https://github.com/basecamp/once-campfire-elixir) at
  `b6b82e5`, one BEAM behind Thruster, linked to system SQLite.
- Go: [once-campfire-go](https://github.com/basecamp/once-campfire-go) at `8d2f7f2`, Go 1.27.1,
  CGO and SQLite FTS5 enabled, one process with `GOMAXPROCS=4`. The benchmark uses its production
  public HTTP listener, with gzip and request logging enabled. Its own saved application
  benchmarks use an internal listener and identity encoding; those settings differ from this run.
- This repo: `eaa05fc`, with application code unchanged from `065ec08`; one BEAM serving HTTP
  itself. Working changes during the run are benchmark harness/docs only.
- Both BEAMs use OTP 28.5 (ERTS 16.4) and Elixir 1.19.5, with explicit `+S 4:4 +SDcpu 4:4`.
  The observed process trees and scheduler counts are recorded in `env.txt`. All apps use the
  installed libvips 8.18; Redis is the existing external instance, cleared before Rails/official runs.

#### Why Go is faster in these scenarios

Go started from an already optimized rewrite. Its
[README at the measured revision](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/README.md)
explicitly identifies it as a Rust port. Its pinned Rust reference, `64f8635`, already includes
the database scheduling, rich-text, rendering and page-part optimizations from
[Rust PR #43](https://github.com/basecamp/once-campfire-rust/pull/43), alongside earlier performance
passes. This gave it a different starting point from the Rails-based specification used here.

The source shows several differences that plausibly explain the measured gap:

- **More work is cached on repeated reads.** Go caches the entire rendered message list used
  by room, history and search pages, the surrounding room-page HTML, and the rendered sidebar.
  It still reads current authorization and page data before using these caches. This repo
  already caches individual message partials, but stitches them together with each request's
  CSRF token and host, and renders the surrounding HEEx templates on every request. The
  repeated seed requests and warmup favor Go's broader caches. See
  [message-list assembly](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/web/recorded.go),
  [room-shell caching](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/web/room_shell.go)
  and [sidebar rendering](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/web/server.go#L425).
- **Warm room/history reads fetch fewer fields.** Go's
  [MessagePageReferences](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/database/messages.go#L314)
  selects only message IDs and update timestamps; author and body loading happens on cache
  misses. Our [page query](lib/campfire/messages.ex) also joins creator fields on cache hits,
  because our fragment keys track creator updates. Go also scans explicit SQL results directly
  into structs and [reuses prepared read statements](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/database/read_pool.go).
  Both implementations already separate WAL readers from a single writer. These are concrete
  differences in query and loading work; their individual contribution has not been measured here.
- **The responses contain less HTML.** In the saved validation probe, Go's room response is
  373,994 bytes versus 468,021 here; its sidebar is 9,462 versus 31,376. In particular, Go's
  [sidebar template](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/web/templates/sidebar.html)
  returns a Turbo-frame fragment, while our sidebar wraps in
  [Layouts.app](lib/campfire_web/components/layouts.ex). The benchmark sends no `Turbo-Frame`
  header, so ours renders the full application document, matching the original Ruby behavior.
  The saved Ruby and official Elixir sidebar responses are both 31,427 bytes. A browser's
  Turbo-frame request includes `Turbo-Frame: user_sidebar`; Ruby and ours then use the minimal
  frame layout. Our [sidebar tests](test/campfire_web/sidebar_test.exs) cover both cases. The
  measured sidebar gap therefore includes a response-shape difference for the benchmark's
  plain GET. A browser-style comparison would send the same frame header to all implementations
  and measure again. Go also follows Rust's
  [Origin/Fetch Metadata policy](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/web/server.go#L301)
  and omits hidden CSRF fields; ours retains Phoenix's token fields. Less HTML means fewer
  bytes to assemble, compress and send. Matching message/room IDs establishes that the same
  records were returned, but does not establish identical HTML or identical rendering work.
- **Go received its own optimization pass after the port.**
  [Go PR #1](https://github.com/basecamp/once-campfire-go/pull/1) added room-shell caching,
  avoided unused rich-text output, and enabled a 64-entry prepared-statement cache on the
  writer. Its [saved comparison](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/bench/results/optimization-next-20261003/README.md)
  reports about 50% more room throughput and 25% more posting throughput over the published
  Go port. Those figures use a different host and the internal application listener, so they
  describe that optimization pass rather than gains measured by our public-listener benchmark.
- **Cable and static assets have separate paths.** Go's
  [Cable hub](https://github.com/basecamp/once-campfire-go/blob/8d2f7f24f56dac87dba0211b68b14d9e21e4b516/internal/cable/hub.go)
  shares prepared messages by subscription identifier and uses bounded outgoing queues.
  Its extension can also share compressed payloads, but our Cable runs used the load generator's
  default uncompressed mode. Both apps already encode broadcast payloads once. Avatar/CSS
  results exercise Go's public response cache and this repo's ETS/static-asset paths, separately
  from the database-backed view rendering above.

The Rust lineage and subsequent targeted optimizations are supported by the source and history.
These measurements compare the resulting implementations. They do not isolate how much of the
gap comes from inherited design, Go-specific optimizations, response differences, or runtime costs;
establishing a primary cause would require profiling and controlled comparisons on this host.

**Host and variability.** The shared host uses the `powersave` CPU governor with turbo enabled.
The harness waits for the 1-minute load average to fall below 3 before each run and records
load at the start and end. Search in this repo varied from 1,494 to 1,790 requests/s at 16
clients; both samples are retained. These are measurements of these implementations and
production process models on this host.

Earlier native results remain in [`linux-20261005-191554`](bench/results/linux-20261005-191554/report.md)
and [`linux-20261005-201440`](bench/results/linux-20261005-201440/report.md). The performance
work (gzip level, scheduler busy-wait, WAL checkpoints, in-memory assets), with measurements
for each change, is in [`bench/PERF.md`](bench/PERF.md).

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
