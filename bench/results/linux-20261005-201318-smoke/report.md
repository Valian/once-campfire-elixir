# Results: linux-20261005-201318-smoke

ours: 1 rep(s)

```
date: 2026-10-05T20:13:18.378843
mode: native (bench/run-native), bare processes, loopback
host: g36-1, 7.0.0-38-generic, 12th Gen Intel(R) Core(TM) i5-12500, 12 threads, 62GB, Ubuntu 26.04.1 LTS
governor: powersave 0
server cpus: 4-7 (siblings 4-5 6-7; process model for 4 cpus); loadgen cpus: 8-11 (siblings 10-11 8-9); harness: 0-3
suites: ['http', 'cable', 'upload'] http secs 3 concs ['16'] cable ['100']
env: WEB_CONCURRENCY=3 JOB_CONCURRENCY=3 RAILS_MAX_THREADS=5 
loadgen: 065ec082e214ed177ec5b199f07867be4bb1bf63 (bench/loadgen)
ours: /home/hermes/orca/workspaces/once-campfire-elixir/server-results @ 065ec082e214ed177ec5b199f07867be4bb1bf63; release erts-16.4 elixir-1.19.5; ELIXIR_ERL_OPTIONS="+S 4:4 +SDcpu 4:4"; VM under taskset 4-7: schedulers_online=4/4 dirty_cpu_schedulers_online=4 dirty_io_schedulers=10 otp=28 elixir=1.19.5
observed ours rep 1: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
```

## Startup and memory

| metric | ours |
|---|---|
| cold start to /up (ms) | 609 |
| idle PSS (MB) | 158 |
| peak PSS (MB) | 315 |
| idle RSS (MB) | 199 |
| peak RSS (MB) | 356 |

## HTTP (median rps, p50/p99 ms)

| route | conc | ours rps | ours p50 | ours p99 | ours bad |
|---|---|---|---|---|---|
| room_show | 16 | 1,199 | 13.1 | 18.7 | 0 |
| messages_page | 16 | 1,465 | 10.8 | 15.8 | 0 |
| sidebar | 16 | 2,299 | 6.91 | 9.25 | 0 |
| search | 16 | 1,895 | 8.41 | 10.6 | 0 |
| avatar | 16 | 37,933 | 0.42 | 0.46 | 0 |
| static_css | 16 | 89,767 | 0.17 | 0.24 | 0 |
| up | 16 | 80,196 | 0.20 | 0.27 | 0 |
| post_message | 16 | 962 | 13.7 | 60.7 | 0 |

## Action Cable fan-out

| clients | metric | ours |
|---|---|---|
| 100 | ready | 100 |
| 100 | connect (s) | 0.06 |
| 100 | fan-out latency p50 (ms) | 7.65 |
| 100 | fan-out latency p99 (ms) | 11.8 |
| 100 | delivered msg/s | 573 |

## Upload (black_hole.jpg, post + thumbnail)

| metric | ours |
|---|---|
| median total (ms) | 40.4 |
