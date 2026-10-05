# Performance log

Hypothesis → measurement → change → result. Machine: M1 Pro, Docker Desktop (10-CPU VM), app
container `--cpus 4`, seed DB bind-mounted (virtiofs), loadgen on the host through Docker's port
forwarder (`bench/README.md`). Unrelated SQL Server and Postgres containers were idle in the same
VM throughout. Single runs vary ±5–10%; numbers below are pairs of alternating A/B runs.

Tools: a prod `mix run` against a seed copy for in-process timings and `:tprof`; inside the
container, `RELEASE_DISTRIBUTION=sname` + `bin/campfire rpc` to attach Ecto telemetry handlers
(per-statement `query_time`/`queue_time`, BEGIN→COMMIT span) or ThousandIsland connection
counters while the loadgen runs.

## 1. Writer path (`POST /rooms/:id/messages`)

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

**Change:** dropped the flags (BEAM defaults). **Result:** post_message +25–50%. Writer occupancy
is ~2.8 ms per message under load, of which ~1.3–1.9 ms is COMMIT I/O; "well under 1 ms" isn't
reachable on this mount without changing the Rails schema or batching commits (group commit),
which this project doesn't want.

Not done: merging statements (exqlite has no multi-statement-with-params), `synchronous=OFF`
(only affects checkpoint fsyncs, ~7%), `locking_mode=EXCLUSIVE` (would lock out the readers).

## 2. Page routes and gzip

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

## 3. `static_css`

**Measurement:** at c=16 css ran at ~11k rps with the container at 430% CPU (quota-bound), while
`/up` did 18k at 190%: Plug.Static costs ~250 µs more per request (two file stats, open +
sendfile through a dirty-IO thread).

**Change:** `CampfireWeb.AssetCache`: at boot, the digested `.css`/`.js` (+ `.gz` siblings,
~4 MB) go into `:persistent_term`; GET/HEAD for those paths are answered from memory with
Plug.Static's headers and gzip/ETag rules (no range support; browsers don't range these). Other
assets fall through to Plug.Static. Digested files never change in place, so a new build means a
new name (served from disk until the next boot).

**Result:** css c=16 10.9k → 17.1k rps, c=64 14.8k → 33k (now at the forwarder's `/up` ceiling).

## 4. Cable readiness at 500/1000 clients

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

## 5. Cable fan-out throughput

Through the forwarder, ours ~21–25 msg/s complete at 1000 clients (official ~12–19). In-network
(both apps on a Docker network, loadgen in a container, 2 runs):

| delivered msg/s | 100 | 500 | 1000 |
|---|---|---|---|
| official | 145–185 | 59–60 | 30–32 |
| ours | 288–301 | 104–157 | 71–93 |

The forwarder caps fan-out at roughly a quarter of what the app delivers; per-socket send-path
tweaks wouldn't show through it. Not pursued.
