# Results: 20261005-130934

reference: 2 rep(s), elixir-official: 2 rep(s)

```
date: 2026-10-05T13:09:35.353341
host: Apple M1 Pro, 10 cores, 16GB, macOS 14.5
docker vm: 10 cpus, 8218034176 bytes, aarch64
limit: --cpus 4 (process model for 4 cpus)
suites: ['http', 'cable', 'upload'] http secs 3 concs ['1', '16'] cable ['100']
env: WEB_CONCURRENCY=3 JOB_CONCURRENCY=3 RAILS_MAX_THREADS=5 
reference image: campfire-reference:app sha256:45452d4756014da9985d453e731fdd4f2b64a4851a01416b2114dbc252e8d8ac 2026-10-05T11:04:29.652520388Z arm64
elixir-official image: campfire-elixir:release sha256:e6becbf0c73acb7eb7a43104016df71a0d86e7be93c3cf39b24d2fd48fe01a84 2026-10-05T11:08:27.320033136Z arm64
```

## Startup and memory

| metric | reference | elixir-official |
|---|---|---|
| cold start to /up (ms) | 5,272 [3,718–6,826] | 1,281 [1,232–1,330] |
| idle memory (MB) | 358 [350–367] | 160 [156–164] |
| peak memory (MB) | 1,564 [1,534–1,594] | 394 [389–399] |

## HTTP (median rps, p50/p99 ms)

| route | conc | reference rps | reference p50 | reference p99 | reference bad | elixir-official rps | elixir-official p50 | elixir-official p99 | elixir-official bad |
|---|---|---|---|---|---|---|---|---|---|
| room_show | 1 | 50.7 [50.6–50.7] | 17.7 | 58.1 | 0 | 136 [135–137] | 7.18 | 10.6 | 0 |
| room_show | 16 | 123 [122–125] | 121 | 362 | 0 | 570 [568–571] | 26.8 | 41.4 | 0 |
| messages_page | 1 | 102 [101–103] | 9.57 | 12.7 | 0 | 174 [174–174] | 5.63 | 8.01 | 0 |
| messages_page | 16 | 220 [219–221] | 65.2 | 174 | 0 | 756 [747–765] | 19.6 | 32.6 | 0 |
| sidebar | 1 | 134 [132–136] | 7.23 | 10.1 | 0 | 210 [205–214] | 4.75 | 7.77 | 0 |
| sidebar | 16 | 360 [357–363] | 43.0 | 85.6 | 0 | 677 [571–782] | 22.5 | 57.4 | 0 |
| search | 1 | 90.4 [85.3–95.5] | 10.9 | 15.3 | 0 | 206 [205–208] | 4.77 | 7.25 | 0 |
| search | 16 | 238 [234–242] | 72.5 | 117 | 0 | 834 [816–853] | 18.6 | 32.6 | 0 |
| avatar | 1 | 2,051 [1,942–2,160] | 0.43 | 1.58 | 0 | 2,051 [2,040–2,063] | 0.42 | 1.44 | 0 |
| avatar | 16 | 14,244 [14,102–14,387] | 0.95 | 3.25 | 0 | 13,074 [12,198–13,950] | 1.02 | 4.03 | 0 |
| static_css | 1 | 2,291 [2,148–2,434] | 0.38 | 1.36 | 0 | 2,214 [2,109–2,319] | 0.40 | 1.40 | 0 |
| static_css | 16 | 15,919 [15,869–15,969] | 0.87 | 3.03 | 0 | 14,783 [13,438–16,127] | 0.91 | 3.84 | 0 |
| up | 1 | 646 [636–655] | 1.39 | 3.88 | 0 | 949 [943–954] | 0.94 | 3.01 | 0 |
| up | 16 | 1,803 [1,686–1,920] | 8.48 | 20.0 | 0 | 5,390 [5,090–5,691] | 2.50 | 13.3 | 0 |
| post_message | 1 | 70.0 [69.1–70.9] | 13.5 | 23.2 | 0 | 92.1 [91.7–92.5] | 10.9 | 15.0 | 0 |
| post_message | 16 | 162 [159–164] | 98.5 | 220 | 0 | 332 [323–342] | 47.2 | 75.1 | 0 |

## Action Cable fan-out

| clients | metric | reference | elixir-official |
|---|---|---|---|
| 100 | ready | 100 | 100 |
| 100 | connect (s) | 0.41 [0.38–0.43] | 0.14 [0.11–0.17] |
| 100 | fan-out latency p50 (ms) | 42.6 [41.4–43.8] | 24.4 [21.9–26.8] |
| 100 | fan-out latency p99 (ms) | 77.0 [67.8–86.1] | 35.9 [35.9–35.9] |
| 100 | delivered msg/s | 48.9 [44.0–53.7] | 119 [119–119] |

## Upload (black_hole.jpg, post + thumbnail)

| metric | reference | elixir-official |
|---|---|---|
| median total (ms) | 159 [151–167] | 176 [174–178] |
