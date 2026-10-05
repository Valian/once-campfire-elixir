# bench

Two harnesses over the same seed, load generator and suites (`lib/common.py`): `run-native` (Linux,
bare processes; the README's primary numbers) and `run` (Docker on macOS). See "Native Linux" below.

Side-by-side benchmark of Campfire implementations in Docker on macOS (Docker Desktop), ported from
[once-campfire-rust](https://github.com/basecamp/once-campfire-rust)'s `bench/run`. Same seed, same
load generator, same suites; see `NOTICE` for what was copied.

## Setup (once)

```sh
bench/make-seed     # clones once-campfire at the pinned commit, builds campfire-reference:app
                    # (native arm64, ~5 min), writes bench/seed/{db,storage,labels.json}
docker build -t campfire-phoenix:app .     # ours
bench/build-elixir-official                # optional: basecamp's Elixir port, native arm64 (~3 min)
```

`bench/run` builds `bench/loadgen` (Rust, `cargo build --release`) itself.

## Run

```sh
bench/run --apps reference,ours                           # 3 reps, full suites (~15 min per app-rep)
HTTP_SECS=3 HTTP_CONCS="1 16" CABLE_CLIENTS=100 bench/run --apps reference,ours --reps 1   # quick
SUITES=http bench/run --apps ours --reps 1
bench/report bench/results/<stamp>                        # re-render the summary
```

Apps: `reference` (`REFERENCE_IMAGE`, default `campfire-reference:app`), `elixir-official`
(`ELIXIR_OFFICIAL_IMAGE`, `campfire-elixir:release`), `ours` (`OURS_IMAGE`, `campfire-phoenix:app`).
The app order alternates between reps. Results: `bench/results/<stamp>/{<app>-<rep>.json, env.txt, report.md}`.

Knobs (env): `CPUS=4` (`docker --cpus`) or `CPUSET=0-3` (`--cpuset-cpus`; also makes `nproc` 4
inside the container), `HTTP_SECS=8`, `HTTP_CONCS="1 16 64"`, `CABLE_CLIENTS="100 500 1000"`,
`CABLE_TPUT_SECS=15`, `CABLE_POSTERS=4`, `UPLOAD_REPS=5`, `PORT=4390`, `SUITES="http cable upload"`,
`SETTLE_SECS=10`, `LOAD_MAX=8`, `LOAD_WAIT_SECS=60` (macOS load average runs high; it is only recorded and waited on), `EXTRA_ENV="K=V ..."`.

## What an image must do

- Serve plain HTTP on container port **80** (published as `127.0.0.1:$PORT`); `GET /up` → 200.
- Use `/rails/storage/db/production.sqlite3` and the Active Storage disk root `/rails/storage/files`
  (bind mounts of a fresh seed copy; writable by the image's default user).
- Take the env in `env.reference` (`SECRET_KEY_BASE`, `VAPID_*`, `DISABLE_SSL=true`, ...) plus
  `WEB_CONCURRENCY`/`JOB_CONCURRENCY`/`RAILS_MAX_THREADS` (free to ignore).
- Speak the Rails app's protocol: `GET /session/new` + `POST /session` (form, CSRF token from the
  `csrf-token` meta, `Sec-Fetch-Site: same-origin`) → 302 with a `session_token` cookie; room pages
  with `<meta name="csrf-token">`, `<turbo-cable-stream-source channel=… signed-stream-name=…>` and
  an `/assets/….css` link; Action Cable at `/cable` with `Origin: http://127.0.0.1:$PORT`.
- No internet: the container runs with `--dns 127.0.0.1`, and the seed's push/webhook endpoints
  are rewritten to a closed local port.

## Caveats vs. the Linux original

- No host networking on Docker Desktop: traffic goes through its port forwarder, which adds latency
  and caps throughput for the cheap routes (`up`, `avatar`, `static_css`). Compare apps with each
  other on this machine, not with the published Linux numbers.
- `--cpus` is a CFS quota, not pinning: `nproc` still reports all VM CPUs, so anything sized from
  the CPU count (the reference's resque-pool, BEAM schedulers unless cgroup-aware) sees 10. Use
  `CPUSET=` when that matters. The load generator shares the Mac's cores with the VM.
- Memory is the container cgroup's `memory.current` (idle) and `memory.peak` (includes page cache).
  The per-process memory breakdown of the original is not ported.

## Native Linux

`bench/run-native` runs each app as a bare process tree (its production process model), pinned
with `taskset` to `SERVER_CPUS` (default 4-7), with the loadgen on `LOADGEN_CPUS` (8-11) over
loopback. One app at a time, fresh seed copy per run, cold start until `/up`, memory as PSS/RSS
of the app's processes from `/proc` (no page cache). Full docs in the script's header.

```sh
bench/setup-native                     # once: loadgen, Rails, official Elixir, Go, ours (mise toolchains)
bench/setup-native go                  # add just Go to an existing native setup
HTTP_SECS=5 bench/run-native --apps reference,elixir-official,go,ours --reps 2
HTTP_SECS=3 HTTP_CONCS=16 CABLE_CLIENTS=100 bench/run-native --apps reference,elixir-official,go,ours --reps 1   # smoke
OURS_REL=/path/to/other/rel SUITES=http bench/run-native --apps ours --reps 1                                # A/B a build
```

- `reference`: Thruster + Puma (`WEB_CONCURRENCY = ceil(0.666 × cpus)`, 5 threads) + resque-pool
  (its `config/resque-pool.yml`: `ceil(0.5 × cpus)` workers), jemalloc, as its Procfile minus Redis.
- `elixir-official`: its release behind Thruster, as its `bin/container-start`.
- `go`: [basecamp/once-campfire-go](https://github.com/basecamp/once-campfire-go), pinned by
  `GO_COMMIT` in `setup-native`, built with CGO and SQLite FTS5. Its production public front end
  serves the benchmark port, including gzip and public asset caching; the internal application
  listener uses the next port. `GOMAXPROCS` equals the pinned CPU count. Go does not use Redis.
- `ours`: `_build/prod/rel/campfire` serving the port itself.
- Both Elixir apps get `ELIXIR_ERL_OPTIONS="+S N:N +SDcpu N:N"` (N = pinned CPUs);
  `env.txt` records what each VM actually reports, and the observed process tree per run.
- Redis is external (`REDIS_URL`, a container on the host), `FLUSHALL`ed before each Rails/official
  run; its memory is reported separately.
- Before each run the harness waits (up to `LOAD_WAIT_SECS`) for the 1-minute load average to
  drop below `LOAD_MAX` and records it.
- Native checkout paths can be overridden with `REFERENCE_DIR`, `ELIXIR_OFFICIAL_DIR` and `GO_DIR`;
  `GO_BIN` overrides the Go executable (`GO_DIR/.native/bin/campfire` by default).
- HTTP requests use `HTTP_GZIP=1` by default; set `HTTP_GZIP=0` for identity encoding across every
  app. Go's own saved application benchmarks use its internal listener and identity encoding,
  so compare those separately from this harness's production front-end measurements.
- Before HTTP timing, the harness compares message/room IDs and avatar bytes with the first
  app's responses. After posting, it checks that every successful request added both a message
  and an FTS entry. These records live under the result directory's `validation/`; failed HTTP
  samples stop the run rather than contributing misleading throughput.
