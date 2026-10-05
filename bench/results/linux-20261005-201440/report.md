# Results: linux-20261005-201440

ours: 2 rep(s)

```
date: 2026-10-05T20:14:40.775507
mode: native (bench/run-native), bare processes, loopback
host: g36-1, 7.0.0-38-generic, 12th Gen Intel(R) Core(TM) i5-12500, 12 threads, 62GB, Ubuntu 26.04.1 LTS
governor: powersave 0
server cpus: 4-7 (siblings 4-5 6-7; process model for 4 cpus); loadgen cpus: 8-11 (siblings 10-11 8-9); harness: 0-3
suites: ['http', 'cable', 'upload'] http secs 5 concs ['1', '16', '64'] cable ['100', '500', '1000']
env: WEB_CONCURRENCY=3 JOB_CONCURRENCY=3 RAILS_MAX_THREADS=5 
loadgen: 065ec082e214ed177ec5b199f07867be4bb1bf63 (bench/loadgen)
ours: /home/hermes/orca/workspaces/once-campfire-elixir/server-results @ 065ec082e214ed177ec5b199f07867be4bb1bf63; release erts-16.4 elixir-1.19.5; ELIXIR_ERL_OPTIONS="+S 4:4 +SDcpu 4:4"; VM under taskset 4-7: schedulers_online=4/4 dirty_cpu_schedulers_online=4 dirty_io_schedulers=10 otp=28 elixir=1.19.5
observed ours rep 1: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
observed ours rep 2: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
```

## Startup and memory

| metric | ours |
|---|---|
| cold start to /up (ms) | 624 [598–649] |
| idle PSS (MB) | 162 [158–165] |
| peak PSS (MB) | 427 [396–458] |
| idle RSS (MB) | 202 [199–206] |
| peak RSS (MB) | 468 [437–499] |

## HTTP (median rps, p50/p99 ms)

| route | conc | ours rps | ours p50 | ours p99 | ours bad |
|---|---|---|---|---|---|
| room_show | 1 | 478 [474–482] | 2.08 | 2.40 | 0 |
| room_show | 16 | 1,204 [1,194–1,213] | 13.1 | 18.6 | 0 |
| room_show | 64 | 1,169 [1,167–1,170] | 54.5 | 61.4 | 0 |
| messages_page | 1 | 619 [616–622] | 1.61 | 1.87 | 0 |
| messages_page | 16 | 1,488 [1,482–1,493] | 10.6 | 15.7 | 0 |
| messages_page | 64 | 1,441 [1,436–1,445] | 44.2 | 50.9 | 0 |
| sidebar | 1 | 1,156 [1,156–1,157] | 0.84 | 1.06 | 0 |
| sidebar | 16 | 2,391 [2,372–2,409] | 6.67 | 8.79 | 0 |
| sidebar | 64 | 2,216 [2,204–2,228] | 28.8 | 32.5 | 0 |
| search | 1 | 758 [755–761] | 1.32 | 1.49 | 0 |
| search | 16 | 1,763 [1,757–1,769] | 9.03 | 11.8 | 0 |
| search | 64 | 1,645 [1,637–1,653] | 38.8 | 42.8 | 0 |
| avatar | 1 | 15,999 [15,983–16,014] | 0.06 | 0.08 | 0 |
| avatar | 16 | 37,516 [37,500–37,532] | 0.41 | 0.61 | 0 |
| avatar | 64 | 38,437 [38,271–38,604] | 1.67 | 1.83 | 0 |
| static_css | 1 | 30,829 [30,790–30,867] | 0.03 | 0.04 | 0 |
| static_css | 16 | 90,336 [89,853–90,818] | 0.18 | 0.28 | 0 |
| static_css | 64 | 88,662 [87,945–89,378] | 0.73 | 0.82 | 0 |
| up | 1 | 31,365 [31,184–31,546] | 0.03 | 0.04 | 0 |
| up | 16 | 80,861 [80,391–81,331] | 0.20 | 0.28 | 0 |
| up | 64 | 80,876 [80,697–81,055] | 0.79 | 0.92 | 0 |
| post_message | 1 | 682 [666–698] | 1.30 | 3.80 | 0 |
| post_message | 16 | 970 [962–977] | 13.8 | 61.3 | 0 |
| post_message | 64 | 948 [939–957] | 57.5 | 129 | 0 |

## Action Cable fan-out

| clients | metric | ours |
|---|---|---|
| 100 | ready | 100 |
| 100 | connect (s) | 0.06 |
| 100 | fan-out latency p50 (ms) | 7.39 [7.12–7.67] |
| 100 | fan-out latency p99 (ms) | 10.1 [9.85–10.3] |
| 100 | delivered msg/s | 580 [579–581] |
| 500 | ready | 500 |
| 500 | connect (s) | 0.22 [0.17–0.27] |
| 500 | fan-out latency p50 (ms) | 12.1 [11.7–12.5] |
| 500 | fan-out latency p99 (ms) | 24.7 [24.0–25.4] |
| 500 | delivered msg/s | 187 [187–188] |
| 1000 | ready | 1,000 |
| 1000 | connect (s) | 0.34 [0.33–0.34] |
| 1000 | fan-out latency p50 (ms) | 16.6 [16.1–17.0] |
| 1000 | fan-out latency p99 (ms) | 35.2 [34.1–36.2] |
| 1000 | delivered msg/s | 97.8 [97.4–98.2] |

## Upload (black_hole.jpg, post + thumbnail)

| metric | ours |
|---|---|
| median total (ms) | 39.5 [38.6–40.5] |
