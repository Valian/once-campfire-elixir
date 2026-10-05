# Results: 20261005-145817

ours: 1 rep(s)

```
date: 2026-10-05T14:58:18.184128
host: Apple M1 Pro, 10 cores, 16GB, macOS 14.5
docker vm: 10 cpus, 8218034176 bytes, aarch64
limit: --cpus 4 (process model for 4 cpus)
suites: ['http', 'cable', 'upload'] http secs 3 concs ['16'] cable ['100']
env: WEB_CONCURRENCY=3 JOB_CONCURRENCY=3 RAILS_MAX_THREADS=5 
ours image: campfire-phoenix:app sha256:17f419ca63f728f59008df1042ab899554d9c8dfffaa8de0bd717efa89381650 2026-10-05T12:58:09.343701293Z arm64
```

## Startup and memory

| metric | ours |
|---|---|
| cold start to /up (ms) | 1,368 |
| idle memory (MB) | 185 |
| peak memory (MB) | 349 |

## HTTP (median rps, p50/p99 ms)

| route | conc | ours rps | ours p50 | ours p99 | ours bad |
|---|---|---|---|---|---|
| room_show | 16 | 909 | 16.0 | 34.9 | 0 |
| messages_page | 16 | 1,131 | 12.3 | 32.3 | 0 |
| sidebar | 16 | 1,609 | 9.92 | 12.5 | 0 |
| search | 16 | 1,321 | 11.0 | 25.0 | 0 |
| avatar | 16 | 15,326 | 0.95 | 2.43 | 0 |
| static_css | 16 | 11,347 | 1.33 | 2.83 | 0 |
| up | 16 | 18,027 | 0.78 | 2.15 | 0 |
| post_message | 16 | 254 | 59.9 | 83.5 | 0 |

## Action Cable fan-out

| clients | metric | ours |
|---|---|---|
| 100 | ready | 100 |
| 100 | connect (s) | 0.12 |
| 100 | fan-out latency p50 (ms) | 21.0 |
| 100 | fan-out latency p99 (ms) | 31.5 |
| 100 | delivered msg/s | 131 |

## Upload (black_hole.jpg, post + thumbnail)

| metric | ours |
|---|---|
| median total (ms) | 96.9 |
