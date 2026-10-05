# Results: linux-20261005-191027-smoke

reference: 1 rep(s), elixir-official: 1 rep(s), ours: 1 rep(s)

```
date: 2026-10-05T19:10:30.211335
mode: native (bench/run-native), bare processes, loopback
host: g36-1, 7.0.0-38-generic, 12th Gen Intel(R) Core(TM) i5-12500, 12 threads, 62GB, Ubuntu 26.04.1 LTS
governor: powersave 0
server cpus: 4-7 (siblings 4-5 6-7; process model for 4 cpus); loadgen cpus: 8-11 (siblings 10-11 8-9); harness: 0-3
suites: ['http', 'cable', 'upload'] http secs 3 concs ['16'] cable ['100']
env: WEB_CONCURRENCY=3 JOB_CONCURRENCY=3 RAILS_MAX_THREADS=5 
loadgen: 51c78be2be1c2091b3294150f1832d80ed58837c (bench/loadgen)
redis (external, shared, FLUSHALL per run): redis://127.0.0.1:6379/0 redis 7.4.11
thruster: /home/hermes/Projects/campfire-bench/reference/vendor/bundle/ruby/3.4.0/gems/thruster-0.1.23-x86_64-linux/exe/x86_64-linux/thrust
reference: /home/hermes/Projects/campfire-bench/reference @ 90b330024dec3e757c79b6a7e6568f93da8e3148; ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]; jemalloc /usr/lib/x86_64-linux-gnu/libjemalloc.so.2; libvips 8.18.0
elixir-official: /home/hermes/Projects/campfire-bench/elixir-official @ b6b82e50a653c4060136bb04e805eb78fd76ba10; release erts-16.4 elixir-1.19.5; ELIXIR_ERL_OPTIONS="+S 4:4 +SDcpu 4:4"; VM under taskset 4-7: schedulers_online=4/4 dirty_cpu_schedulers_online=4 dirty_io_schedulers=10 otp=28 elixir=1.19.5
ours: /home/hermes/orca/workspaces/once-campfire-elixir/server-results @ 51c78be2be1c2091b3294150f1832d80ed58837c; release erts-16.4 elixir-1.19.5; ELIXIR_ERL_OPTIONS="+S 4:4 +SDcpu 4:4"; VM under taskset 4-7: schedulers_online=4/4 dirty_cpu_schedulers_online=4 dirty_io_schedulers=10 otp=28 elixir=1.19.5
observed reference rep 1: puma workers 3 (OS threads per worker [13, 12, 12], RAILS_MAX_THREADS 5); resque workers 2; 10 processes: jobs, other, puma, thrust
observed elixir-official rep 1: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 2 processes: beam, thrust
observed ours rep 1: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
```

## Startup and memory

| metric | reference | elixir-official | ours |
|---|---|---|---|
| cold start to /up (ms) | 2,746 | 565 | 670 |
| idle PSS (MB) | 315 | 139 | 159 |
| peak PSS (MB) | 1,081 | 320 | 270 |
| idle RSS (MB) | 989 | 175 | 200 |
| peak RSS (MB) | 1,549 | 356 | 311 |
| external Redis RSS at end (MB) | 13.6 | 22.0 | – |

## HTTP (median rps, p50/p99 ms)

| route | conc | reference rps | reference p50 | reference p99 | reference bad | elixir-official rps | elixir-official p50 | elixir-official p99 | elixir-official bad | ours rps | ours p50 | ours p99 | ours bad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| room_show | 16 | 136 | 107 | 300 | 0 | 467 | 34.0 | 44.4 | 0 | 1,117 | 14.1 | 19.6 | 0 |
| messages_page | 16 | 266 | 58.4 | 117 | 0 | 628 | 25.2 | 37.5 | 0 | 1,334 | 11.9 | 17.5 | 0 |
| sidebar | 16 | 345 | 43.6 | 115 | 0 | 786 | 20.3 | 25.2 | 0 | 1,978 | 8.05 | 10.3 | 0 |
| search | 16 | 256 | 57.7 | 115 | 0 | 750 | 21.2 | 26.2 | 0 | 1,656 | 9.62 | 12.5 | 0 |
| avatar | 16 | 55,404 | 0.21 | 1.14 | 0 | 56,550 | 0.20 | 1.16 | 0 | 33,138 | 0.48 | 0.60 | 0 |
| static_css | 16 | 69,607 | 0.18 | 0.94 | 0 | 68,935 | 0.18 | 0.97 | 0 | 89,925 | 0.17 | 0.24 | 0 |
| up | 16 | 2,800 | 5.58 | 11.0 | 0 | 4,845 | 3.23 | 7.17 | 0 | 80,440 | 0.20 | 0.26 | 0 |
| post_message | 16 | 168 | 85.4 | 228 | 0 | 460 | 30.9 | 56.0 | 0 | 945 | 13.9 | 65.3 | 0 |

## Action Cable fan-out

| clients | metric | reference | elixir-official | ours |
|---|---|---|---|---|
| 100 | ready | 100 | 100 | 100 |
| 100 | connect (s) | 0.34 | 0.12 | 0.06 |
| 100 | fan-out latency p50 (ms) | 30.9 | 10.2 | 7.17 |
| 100 | fan-out latency p99 (ms) | 66.2 | 23.6 | 10.1 |
| 100 | delivered msg/s | 59.3 | 230 | 562 |

## Upload (black_hole.jpg, post + thumbnail)

| metric | reference | elixir-official | ours |
|---|---|---|---|
| median total (ms) | 67.1 | 86.5 | 40.5 |
