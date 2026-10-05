# Performance log

Two passes. The second, natively on Linux, is the one the README's primary numbers come from. The
first, on a laptop under Docker Desktop, is kept below because it found the gzip and static
asset costs; some of its conclusions did not survive native measurement (noted inline).

## Part 1: native Linux (`bench/run-native`)

Host: Intel i5-12500 (6 cores / 12 threads), 62 GB, Ubuntu 26.04, kernel 7.0, xfs on an NVMe
RAID1 (md). The app is pinned with taskset to CPUs 4-7 (two physical cores with their HT
siblings), the loadgen to 8-11, the harness to 0-3; `+S 4:4 +SDcpu 4:4`. The machine is shared,
so every comparison below is a pair of alternating runs (`HTTP_SECS=5`, c = 1/16/64, HTTP suite
only, fresh seed each run); runs of the same build agree within ~3%.

Tools: a prod `mix run` of the app under the same taskset with Ecto telemetry attached to the
writer (per-statement `query_time`, BEGIN→COMMIT span, pool idle time → occupancy),
`/proc/self/task/*/schedstat` for per-thread run/runqueue time, `:tprof`, `strace -c`, and a
standalone exqlite loop that replays the five statements of a post (to isolate COMMIT).
Variant releases for A/B are `mix release --path` builds run with `OURS_REL=`.

### Summary

| Issue | Root cause | Fix | Before → after (c=16 unless noted) |
|---|---|---|---|
| Posting: writer held ~1.25 ms per message under load, COMMIT ~420 µs | Default WAL autocheckpoint (1000 pages ≈ every 60 messages) runs inside a commit and fsyncs WAL + DB on the md RAID1: p99 COMMIT 15 ms, mean 390 µs | `PRAGMA wal_autocheckpoint = 4000` on the writer (`Campfire.Repo.after_connect/1`; exqlite's `custom_pragmas` can't set it, `journal_mode=WAL` resets it) | post 797 → 968 rps (+21%); c=1 640 → 712, p99 16.4 → 3.8 ms; COMMIT 420 → 220 µs; c=16 p99 45 → 65 ms (bigger, rarer stalls) |
| Every DB route slower than it should be under load | Idle dirty schedulers busy-wait (BEAM default); 10 dirty IO + 4 dirty CPU threads spinning on 4 CPUs steal time from the request processes | `+sbwtdcpu none +sbwtdio none` in `rel/vm.args.eex` | room 1,011 → 1,120 (+11%), messages +10%, sidebar +9%, search +6%, post +12%; c=1 −1…−5% |
| Room/messages/search pages CPU-bound on gzip | Bandit gzips with `:zlib.gzip/1`, fixed at level 6 (2.2 ms for the 468 KB room page) | `CampfireWeb.Gzip` at level 3 (1.0 ms, 28 KB instead of 22 KB); zstd clients left to Bandit | room 760 → 1,095 (+44%), messages 937 → 1,300 (+39%), search 1,312 → 1,670 (+27%) |
| CSS/JS from disk on every request | `Plug.Static` stats + opens + sendfiles per request | `CampfireWeb.AssetCache` (`:persistent_term`, prod only) | static CSS 26.4k → 89k rps (3.4×), c=1 12.1k → 29.3k; p99 2.7 → 0.3 ms |
| Remaining writer stretch under load | exqlite marks every NIF dirty-IO, ~6 dirty calls per statement (~40 per post), each a thread hand-off | not changed here (dependency); upstream suggestion, measured below | patched exqlite: post 953 → 1,117 (+17%) |

Altogether, against the `perf-wip` starting point measured natively (gzip 3 and the asset
cache already in, BEAM-default busy-wait, default checkpoints), posting went from 720–726 to
967–969 rps at c=16 (+34%) and the room page from 1,002–1,020 to 1,081–1,110 (+8%).

### N1. Writer path (`POST /rooms/:id/messages`)

**Hypothesis (from the review):** ~3.6 ms of writer occupancy per message; something avoidable
inside the transaction.

**Measurement.** The transaction already held only the writes: BEGIN IMMEDIATE, message insert
(RETURNING), rich text, room touch, FTS row, one unread `UPDATE` for all members, COMMIT.
Parsing, the attachment, rendering, the broadcast and every read are outside it, each write is
a single statement. Natively (c=1, telemetry on the writer):

| | tmpfs (first, misleading) | xfs, before | xfs, after |
|---|---|---|---|
| BEGIN→COMMIT | 310 µs | 772 µs | ~400 µs |
| COMMIT | 31 µs | 415 µs | 57–212 µs (mean incl. checkpoints) |
| statements (5) | 16–43 µs each | 27–60 µs each | same |
| post rps / p99 (c=1) | 892 / 1.3 ms | 598 / 16 ms | 712 / 3.8 ms |

So the macOS 3.6 ms was virtiofs; natively the statements are cheap and COMMIT was the cost.
`strace -c` showed only ~28 `pwrite`s per message (≈1 µs each) and occasional `fsync`s, and the
replay loop isolated it:

| writer `wal_autocheckpoint` | COMMIT mean | p50 | p99 | max |
|---|---|---|---|---|
| 1000 (default) | 386–405 µs | 41–57 µs | 14.6–15.2 ms | 30–37 ms |
| 2000 | 241 µs | 33 µs | 5.8 ms | 37 ms |
| **4000** | 159–169 µs | 33–37 µs | 106–178 µs | 32–38 ms |
| 8000 | 129 µs | 36 µs | 170 µs | 57 ms |
| 0 (never) | 47 µs | 40 µs | 93 µs | 17 ms |

A checkpoint costs about the same at 1000 and 4000 pages (~30 ms, mostly the two fsyncs on the
RAID1), so checkpointing a quarter as often removes ~60% of the average COMMIT without making
the stall longer; beyond 4000 the stall grows. **Change:** `wal_autocheckpoint = 4000` on the
writer connection (WAL up to ~16 MB; `journal_size_limit` stays 64 MB). It has to be an
`after_connect` (`Campfire.Repo.after_connect/1`): exqlite applies `custom_pragmas` before
`journal_mode=WAL`, which resets the value. The config looked right but `PRAGMA
wal_autocheckpoint` still answered 1000. Durability is unchanged (`synchronous=NORMAL`: only
checkpoints sync).

**Rejected:** checkpointing from a separate connection (a GenServer doing `wal_checkpoint(PASSIVE)`
every second, writer autocheckpoint off). COMMIT fell to ~57 µs and posting to 1,129 rps, but a
passive checkpoint never catches up with a writer that keeps appending, so the WAL never restarts:
1.17 GB after 20 s of posting. Making it complete needs `RESTART`/`TRUNCATE`, which block the
writer anyway; a larger autocheckpoint gets most of the gain with one line.

**Result** (harness, 2 alternating runs each, `ckpt1000` = the same build with the default):

| post_message rps (p99 ms) | c=1 | c=16 | c=64 |
|---|---|---|---|
| default 1000 pages | 621–659 (16.4) | 770–823 (45) | 807–817 (102) |
| 4000 pages | 703–721 (3.8) | 967–969 (65) | 936–937 (110) |

The tail at c=16/64 is the trade: a stall now holds up to ~16 queued posts for ~30 ms a quarter
as often. Other routes are unaffected.

**Writer occupancy now:** ~0.4 ms per message uncontended (c=1: 32–39% busy at 700–800 rps). At
saturation (c≥16, writer 99.8% busy) it is 1/throughput ≈ 1.0 ms: every statement takes 3–4×
longer (100–160 µs) than uncontended. Not the run queue (raising the posting process to
`:high` priority changed nothing) and not CPU saturation (the VM uses ~2.5 of 4 CPUs): exqlite
declares every NIF dirty-IO, including trivial ones (`changes`, `transaction_status`,
`columns`, `release`), so a statement is ~6 hand-offs to a dirty IO thread and back, ~40 per
post, each a thread wake-up when threads don't spin. Making those four NIFs regular
(experiment only, `sqlite3_nif.c` flags, built from source on both sides):

| rps, 2 runs each | post c=1 | post c=16 | post c=64 | search c=16 | room c=16 |
|---|---|---|---|---|---|
| exqlite 0.42 from source | 707–716 | 935–971 | 914–925 | 1,620–1,644 | 1,117–1,124 |
| trivial NIFs not dirty | 756–776 | 1,101–1,132 | 1,070–1,083 | 1,718–1,741 | 1,153–1,161 |

That's +17% for posting and a few % for every read route, with no app change: worth proposing
upstream (they take a connection mutex, which is uncontended under DBConnection's one-user-at-a-
time ownership but has to be argued for `interrupt`). Not shipped here: no forked dependencies.

Also measured and not pursued: the turbo-stream broadcast's `Jason.encode!` of the ~9 KB message
HTML is ~50 µs (`:tprof` call_time overstated it at 16%; Elixir's `JSON` is ~20% faster, a ~10 µs
saving); scheduler priority (no effect).

### N2. Scheduler busy-wait

`perf-wip` had reverted `+sbwt none +sbwtdcpu none +sbwtdio none` to the BEAM defaults on the
strength of the macOS measurement (M1 below). Natively the per-thread schedstat told a different
story: at c=16 the dirty IO threads ran 8.6 s of CPU in a 5 s window (1.7 cores) for ~1 s of
SQLite work and waited 10 s in the OS run queue; normal schedulers waited 4 s. Spinning dirty
threads (10 IO + 4 CPU, sized for the host, not the pin) compete with the schedulers for 4 CPUs.

| rps (2 runs each) | room c=16 | messages c=16 | sidebar c=16 | search c=16 | post c=1 | post c=16 | post c=64 |
|---|---|---|---|---|---|---|---|
| BEAM defaults | 1,002–1,020 | 1,216–1,227 | 1,737–1,790 | 1,522–1,549 | 631–637 | 720–726 | 703–708 |
| `+sbwtdcpu none +sbwtdio none` | 1,118–1,122 | 1,345–1,347 | 1,892–1,967 | 1,612–1,638 | 606–607 | 785–835 | 782–804 |
| all three `none` | 1,115–1,136 | 1,304–1,337 | 1,786–1,798 | 1,605–1,614 | 590–597 | 740–765 | 754–772 |

At c=1 the defaults are 1–5% faster (a spinning thread answers sooner); at c=16/64 dirty-off is
6–13% faster on every DB route, and the BEAM's CPU per post drops from 3.9 to 2.5 ms. Turning
normal-scheduler spinning off too is no better. Avatar, CSS and `/up` are unchanged in all three.
**Change:** `+sbwtdcpu none +sbwtdio none` (normal schedulers at the default). The macOS result
(defaults best) was measured through Docker Desktop's VM, where thread wake-ups are expensive;
natively they aren't, and the oversubscription dominates.

### N3. Gzip

**Bandit config?** No. Bandit 1.12.5 (mix.lock) negotiates `zstd` (when OTP has `:zstd`, as 28
does), `gzip`, `x-gzip`, `deflate`, in that order (`response_encodings` can reorder them).
`deflate_options` (level, window bits, ...) apply to `deflate` only; `gzip` is always
`:zlib.gzip/1`, i.e. level 6. So the plug stays, and it is already minimal: a substring check of
`Accept-Encoding` (gzip and not zstd; no q-values), `before_send`, Bandit's own skip rules.

**Does zstd matter?** Yes: Bandit really serves zstd to browsers (`Accept-Encoding: gzip,
deflate, br, zstd` → `content-encoding: zstd`, 16.9 KB for the room page), so the plug must
leave those clients alone. The loadgen sends `gzip` only. Cost of one room page (468 KB, one
core, 200 iterations):

| | time | size |
|---|---|---|
| gzip level 6 (Bandit) | 2.18 ms | 21.7 KB |
| gzip level 3 (`CampfireWeb.Gzip`) | 1.03 ms | 27.6 KB |
| gzip level 1 | 1.13 ms | 35.2 KB |
| zstd, default level (Bandit) | 0.23 ms | 16.5 KB |

**Result** (same build with and without the plug, 2 runs each):

| rps (p99 ms) | room c=16 | room c=64 | messages c=16 | search c=16 | sidebar c=16 |
|---|---|---|---|---|---|
| Bandit level 6 | 759–760 (29.6) | 741–748 | 932–942 (24.8) | 1,300–1,324 (15.7) | 1,742–1,767 |
| level 3 | 1,081–1,110 (21.7) | 1,060–1,072 | 1,280–1,320 (18.5) | 1,609–1,734 (12.8) | 1,782–1,910 |

Bytes on the wire: room 22.2 → 28.3 KB, messages 13.4 → 18.2 KB, search 9.6 → 12.1 KB.

**Upstream:** yes, a gzip level in Bandit is the right fix. Gzip is deflate with a different
wrapper (`windowBits` 31); `start_stream("gzip", ...)` could take a `gzip_options: [level: ...]`
(or honour `deflate_options[:level]`) through `deflateInit` exactly as the deflate path does.
Bandit already owns negotiation and the skip rules, which this plug has to duplicate; with that
option it becomes `http_options: [gzip_options: [level: 3]]` and the module goes.

### N4. Static CSS/JS

`CampfireWeb.AssetCache` is unchanged in size (one module, ~90 lines): boot-time
`:persistent_term` of the digested `.css`/`.js` and their `.gz`, Plug.Static's headers. Dev no
longer loads it (`config :campfire, cache_assets: false`), so editing a file under
`priv/static/assets` shows up on the next request (checked: edited `_reset-*.css` served at once).

**Result** (same build with and without the plug; final: 3 runs, without: 2):

| static_css rps (p99 ms) | c=1 | c=16 | c=64 |
|---|---|---|---|
| Plug.Static from disk | 11,796–12,358 | 26,259–26,598 (2.7) | 29,932–29,955 (5.7) |
| `AssetCache` | 28,266–30,023 | 88,846–89,891 (0.3) | 85,295–87,960 (1.0) |

Natively the gap is bigger than on macOS (3.4× vs 1.6× at c=16): without Docker's forwarder in
the way, the per-request stat/open/sendfile through a dirty-IO thread is the whole cost. The
cache now runs at the `/up` ceiling (~80k), like Thruster in front of the other two apps. Other
routes are unchanged within noise.

### N5. Cable connection resets

They don't reproduce natively. In the full run (`results/linux-20261005-191554`) every
cable sample of every app reached 100/500/1,000 ready in both reps, and the loadgen's per-run
stderr has no connection errors. Ours connects 1,000 clients in 0.33 s (official 0.60 s, Rails
2.4 s). That fits M4's conclusion: the resets came from Docker Desktop's port forwarder, not
the app. No change.

## Part 2: macOS / Docker Desktop (first pass)

Hypothesis → measurement → change → result. Machine: M1 Pro, Docker Desktop (10-CPU VM), app
container `--cpus 4`, seed DB bind-mounted (virtiofs), loadgen on the host through Docker's port
forwarder (`bench/README.md`). Unrelated SQL Server and Postgres containers were idle in the same
VM throughout. Single runs vary ±5–10%; numbers below are pairs of alternating A/B runs.

Tools: a prod `mix run` against a seed copy for in-process timings and `:tprof`; inside the
container, `RELEASE_DISTRIBUTION=sname` + `bin/campfire rpc` to attach Ecto telemetry handlers
(per-statement `query_time`/`queue_time`, BEGIN→COMMIT span) or ThousandIsland connection
counters while the loadgen runs.

### M1. Writer path (`POST /rooms/:id/messages`)

**Hypothesis:** the writer transaction is too big or does avoidable work.

**Measurement.** The transaction is already minimal: BEGIN IMMEDIATE, 5 statements (message
insert with RETURNING, rich text, room touch, FTS row, one unread `UPDATE` for all members),
COMMIT. Rendering, broadcast and the member/ban/membership reads are all outside it. Inside the
container, at c=1:

| | per message |
|---|---|
| BEGIN→COMMIT span | 2.3–2.6 ms |
| COMMIT | 1.15 ms (p50 1.3 ms, p99 6 ms incl. autocheckpoints, ~7% of commit time) |
| each statement | 120–260 µs (30–150 µs in a tight in-process loop) |
| a trivial read (`SELECT 1 FROM bans …`) | 35 µs idle, 230 µs right after writes |

A message dirties 16 pages (WAL frames: messages + its 3 indexes, sqlite_sequence, rich text +
unique index, FTS5 ×6 (data/idx/docsize/content)); SQLite writes a frame as two `pwrite`s, so a
commit is ~32 writes through virtiofs at ~40 µs each. With the same DB copied to the container's
own filesystem (diagnostic only, `DATABASE_PATH=/tmp/db/...`), POST goes from ~340 to **~900 rps**
(c=16) and becomes CPU-bound. So the cap is the bind mount's per-syscall latency, which every app
in the benchmark pays (the official port keeps one connection for everything and pays it too).
The schema is Rails' (FTS5 table, indexes), so the frame count is fixed; our one extra index
(`room_id, created_at`) is one of the 16 frames and is what the room page needs.

**Second finding:** `rel/vm.args.eex` had `+sbwt none +sbwtdcpu none +sbwtdio none`. Every
exqlite call is a dirty-IO NIF, so each statement hopped to a sleeping dirty thread and back to a
sleeping scheduler; in the VM a thread wake-up costs tens of µs. Measured (2 alternating runs each):

| post_message rps | c=1 | c=16 | c=64 |
|---|---|---|---|
| `+sbwt* none` (before) | 164–183 | 260–276 | 231 |
| `+sbwtdio short` only | 194–237 | 321–335 | 303–304 |
| `+sbwt medium` only | 207–227 | 309–320 | 310–314 |
| BEAM defaults (both) | 203–228 | 341–363 | 335–357 |

GET routes were unchanged within noise (room_show, sidebar, search, css, up).

**Change:** dropped the flags (BEAM defaults). **Result:** post_message +25–50%. (Natively this
did not hold for the dirty schedulers: see N2.) Writer occupancy
is ~2.8 ms per message under load, of which ~1.3–1.9 ms is COMMIT I/O; "well under 1 ms" isn't
reachable on this mount without changing the Rails schema or batching commits (group commit),
which this project doesn't want.

Not done: merging statements (exqlite has no multi-statement-with-params), `synchronous=OFF`
(only affects checkpoint fsyncs, ~7%), `locking_mode=EXCLUSIVE` (would lock out the readers).

### M2. Page routes and gzip

**Measurement** (prod, in-process, per request, single process):

| route | body | app (routing → render) | gzip (zlib level 6) | level 1 | level 3 | level 4 |
|---|---|---|---|---|---|---|
| room_show | 468 KB | 1.1–1.6 ms | 2.7 ms → 22.1 KB | 1.0 ms → 36 KB | 1.0 ms → 29 KB | 2.2 ms → 27 KB |
| messages_page | 435 KB | 0.8 ms | 2.1 ms → 13.3 KB | 0.8 ms → 25 KB | 0.7 ms → 18.8 KB | 1.9 ms → 18.6 KB |
| search | 167 KB | 0.7 ms | 1.0 ms → 9.5 KB | 0.4 ms → 14 KB | 0.35 ms → 12 KB | 0.8 ms → 11 KB |
| sidebar | 31 KB | 0.7 ms | 0.3 ms → 5.9 KB | 0.1 ms → 6.7 KB | 0.12 ms → 6.5 KB | 0.2 ms → 6.1 KB |

Gzip was ~65% of the room page's CPU. Bandit 1.12 gzips with `:zlib.gzip/1`, fixed at level 6;
its `deflate_options` only apply to the `deflate` encoding. zlib levels 1–3 use the fast
(lazy-match-free) strategy, which is why 3 costs the same as 1 here while compressing much better.

Thruster (in front of the Rails app) gzips at level 6 too, but with klauspost/compress, which is
considerably faster than zlib at the same level; Rails' level-6 bytes are therefore not bought at
zlib's level-6 price. Browsers send `zstd`, which Bandit prefers (room page 16.9 KB, cheaper than
gzip-6), so for them nothing changes; the loadgen sends `Accept-Encoding: gzip` only.

**Change:** `CampfireWeb.Gzip`, a `before_send` plug that gzips at level 3 when the client takes
gzip but not zstd, with Bandit's skip rules (204/304, empty, no-transform, strong ETag, already
encoded). The right long-term fix is a `level` option for gzip in Bandit; then this plug goes.

**Result** (c=16, 2 alternating runs): room_show 869–904 → 1187–1280 rps (+39%), messages_page
903–962 → 1456–1487 (+58%), search 1331–1373 → 1393–1420, sidebar unchanged. Bytes: room
22.2 → 28.3 KB, messages 13.4 → 18.2 KB.

**Remaining app time** is flat (`:tprof` call_time, room page): Ecto loading (type loaders,
timestamp parsing) ~25%, HEEx escaping/iodata ~10%, exqlite ~6%, `Application.get_env` from
ecto_sqlite3's loaders ~6%, nothing above 6% per function. CSRF: one masked token per request,
spliced into the fragment-cached message partials (8 forms × 40 messages share it), so no
per-form masking. Not pursued further.

### M3. `static_css`

**Measurement:** at c=16 css ran at ~11k rps with the container at 430% CPU (quota-bound), while
`/up` did 18k at 190%: Plug.Static costs ~250 µs more per request (two file stats, open +
sendfile through a dirty-IO thread).

**Change:** `CampfireWeb.AssetCache`: at boot, the digested `.css`/`.js` (+ `.gz` siblings,
~4 MB) go into `:persistent_term`; GET/HEAD for those paths are answered from memory with
Plug.Static's headers and gzip/ETag rules (no range support; browsers don't range these). Other
assets fall through to Plug.Static. Digested files never change in place, so a new build means a
new name (served from disk until the next boot).

**Result:** css c=16 10.9k → 17.1k rps, c=64 14.8k → 33k (now at the forwarder's `/up` ceiling).

### M4. Cable readiness at 500/1000 clients

**Hypothesis A:** replica pool queueing on subscribe (6 subscriptions × N clients, 4 readers).
Server logs stay empty (a dropped checkout would crash the socket and log).

**Measurement:** reproduced only through the host port forwarder and only after the HTTP suite
(3/3 sequences: 1000 clients → 841–945 ready; 500 → 435–500). The patched loadgen prints the
error: `Connection reset by peer` during the WebSocket handshake. Counting ThousandIsland
`connection.start` inside the app in a run where 48 of 1000 failed: 957 TCP connections = 952
WebSockets + 5 HTTP, i.e. **the failed connections never reached the app**. With the loadgen in a
container on the same Docker network (linux build), 0 failures in 5/5 sequences (100/500/1000).
Listener defaults are fine (100 acceptors, backlog 1024, 50 handshakes in flight from the loadgen).

**Conclusion:** Docker Desktop's port forwarder resets connections under that burst. Why it hits
ours and not the official port through the same forwarder is not established; ours completes
handshakes faster (connect 0.3–0.7 s vs 0.4–0.8 s). No app change.

### M5. Cable fan-out throughput

Through the forwarder, ours ~21–25 msg/s complete at 1000 clients (official ~12–19). In-network
(both apps on a Docker network, loadgen in a container, 2 runs):

| delivered msg/s | 100 | 500 | 1000 |
|---|---|---|---|
| official | 145–185 | 59–60 | 30–32 |
| ours | 288–301 | 104–157 | 71–93 |

The forwarder caps fan-out at roughly a quarter of what the app delivers; per-socket send-path
tweaks wouldn't show through it. Not pursued.
