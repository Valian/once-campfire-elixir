# Results: linux-20261005-191554

reference: 2 rep(s), elixir-official: 2 rep(s), ours: 2 rep(s)

```
date: 2026-10-05T19:15:55.089391
mode: native (bench/run-native), bare processes, loopback
host: g36-1, 7.0.0-38-generic, 12th Gen Intel(R) Core(TM) i5-12500, 12 threads, 62GB, Ubuntu 26.04.1 LTS
governor: powersave 0
server cpus: 4-7 (siblings 4-5 6-7; process model for 4 cpus); loadgen cpus: 8-11 (siblings 10-11 8-9); harness: 0-3
suites: ['http', 'cable', 'upload'] http secs 5 concs ['1', '16', '64'] cable ['100', '500', '1000']
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
observed ours rep 2: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
observed elixir-official rep 2: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 2 processes: beam, thrust
observed reference rep 2: puma workers 3 (OS threads per worker [12, 13, 12], RAILS_MAX_THREADS 5); resque workers 2; 10 processes: jobs, other, puma, thrust
```

## Startup and memory

| metric | reference | elixir-official | ours |
|---|---|---|---|
| cold start to /up (ms) | 2,849 [2,832–2,866] | 567 [566–568] | 662 [650–673] |
| idle PSS (MB) | 313 [311–315] | 141 [139–144] | 156 [154–158] |
| peak PSS (MB) | 1,305 [1,256–1,354] | 536 [534–538] | 450 [402–498] |
| idle RSS (MB) | 979 [968–990] | 178 [175–180] | 197 [195–199] |
| peak RSS (MB) | 1,769 [1,719–1,820] | 572 [570–575] | 491 [442–539] |
| external Redis RSS at end (MB) | 18.0 [17.7–18.4] | 36.9 [36.0–37.7] | – |

## HTTP (median rps, p50/p99 ms)

| route | conc | reference rps | reference p50 | reference p99 | reference bad | elixir-official rps | elixir-official p50 | elixir-official p99 | elixir-official bad | ours rps | ours p50 | ours p99 | ours bad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| room_show | 1 | 68.5 [68.3–68.8] | 13.9 | 25.1 | 0 | 224 [220–228] | 4.44 | 5.02 | 0 | 452 [449–455] | 2.21 | 2.51 | 0 |
| room_show | 16 | 142 [142–142] | 102 | 250 | 0 | 465 [464–466] | 34.1 | 44.9 | 0 | 1,087 [1,052–1,121] | 14.6 | 20.8 | 0 |
| room_show | 64 | 139 [132–146] | 439 | 613 | 0 | 460 [458–462] | 138 | 156 | 0 | 1,067 [1,042–1,092] | 59.6 | 68.1 | 0 |
| messages_page | 1 | 128 [127–129] | 7.74 | 9.38 | 0 | 297 [297–298] | 3.33 | 3.90 | 0 | 557 [551–564] | 1.79 | 2.02 | 0 |
| messages_page | 16 | 263 [260–266] | 57.4 | 120 | 0 | 626 [624–628] | 25.3 | 37.3 | 0 | 1,314 [1,311–1,317] | 12.1 | 18.1 | 0 |
| messages_page | 64 | 262 [260–263] | 242 | 318 | 0 | 623 [621–625] | 102 | 123 | 0 | 1,289 [1,280–1,298] | 49.3 | 56.4 | 0 |
| sidebar | 1 | 163 [154–172] | 5.77 | 11.8 | 0 | 549 [540–558] | 1.78 | 2.24 | 0 | 977 [976–977] | 1.00 | 1.26 | 0 |
| sidebar | 16 | 350 [340–361] | 44.3 | 86.2 | 0 | 779 [766–791] | 20.4 | 25.4 | 0 | 1,881 [1,867–1,895] | 8.47 | 10.9 | 0 |
| sidebar | 64 | 346 [340–352] | 178 | 266 | 0 | 807 [804–809] | 79.1 | 88.7 | 0 | 1,790 [1,774–1,806] | 35.7 | 39.4 | 0 |
| search | 1 | 124 [124–125] | 7.94 | 9.65 | 0 | 426 [414–438] | 2.33 | 2.73 | 0 | 728 [720–735] | 1.37 | 1.56 | 0 |
| search | 16 | 266 [265–267] | 60.1 | 111 | 0 | 796 [756–837] | 20.0 | 24.9 | 0 | 1,609 [1,592–1,627] | 9.90 | 12.8 | 0 |
| search | 64 | 258 [255–260] | 245 | 320 | 0 | 810 [764–856] | 78.9 | 86.7 | 0 | 1,535 [1,521–1,549] | 41.6 | 46.2 | 0 |
| avatar | 1 | 17,036 [17,023–17,049] | 0.05 | 0.17 | 0 | 17,799 [17,633–17,966] | 0.05 | 0.16 | 0 | 12,902 [11,741–14,063] | 0.08 | 0.10 | 0 |
| avatar | 16 | 50,334 [50,046–50,622] | 0.22 | 1.36 | 0 | 51,450 [50,701–52,198] | 0.21 | 1.38 | 0 | 32,316 [31,789–32,842] | 0.53 | 0.72 | 0 |
| avatar | 64 | 40,230 [40,156–40,305] | 0.78 | 8.98 | 0 | 41,764 [41,638–41,890] | 0.74 | 8.84 | 0 | 33,346 [32,367–34,325] | 1.91 | 2.15 | 0 |
| static_css | 1 | 21,557 [21,497–21,617] | 0.04 | 0.11 | 0 | 21,288 [20,873–21,702] | 0.04 | 0.11 | 0 | 30,186 [29,832–30,540] | 0.03 | 0.04 | 0 |
| static_css | 16 | 65,299 [65,256–65,342] | 0.18 | 1.02 | 0 | 64,117 [63,542–64,692] | 0.18 | 1.09 | 0 | 89,302 [88,924–89,680] | 0.18 | 0.27 | 0 |
| static_css | 64 | 55,270 [55,114–55,427] | 0.70 | 6.06 | 0 | 54,633 [54,548–54,717] | 0.67 | 6.26 | 0 | 87,835 [87,405–88,266] | 0.73 | 0.80 | 0 |
| up | 1 | 1,390 [1,384–1,396] | 0.69 | 1.10 | 0 | 2,466 [2,466–2,467] | 0.40 | 0.58 | 0 | 31,531 [30,942–32,121] | 0.03 | 0.04 | 0 |
| up | 16 | 2,783 [2,760–2,806] | 5.58 | 11.0 | 0 | 4,885 [4,815–4,954] | 3.12 | 7.54 | 0 | 80,232 [79,952–80,512] | 0.20 | 0.29 | 0 |
| up | 64 | 2,748 [2,730–2,766] | 23.0 | 34.8 | 0 | 4,971 [4,910–5,032] | 12.1 | 28.8 | 0 | 79,681 [79,641–79,720] | 0.80 | 0.94 | 0 |
| post_message | 1 | 99.0 [96.6–101] | 8.90 | 39.6 | 0 | 259 [258–260] | 3.51 | 16.4 | 0 | 687 [686–688] | 1.29 | 4.08 | 0 |
| post_message | 16 | 165 [164–166] | 87.8 | 234 | 0 | 487 [449–525] | 29.2 | 54.4 | 0 | 952 [937–966] | 14.0 | 63.2 | 0 |
| post_message | 64 | 166 [166–167] | 374 | 545 | 0 | 532 [500–564] | 120 | 143 | 0 | 932 [929–936] | 58.5 | 113 | 0 |

## Action Cable fan-out

| clients | metric | reference | elixir-official | ours |
|---|---|---|---|---|
| 100 | ready | 100 | 100 | 100 |
| 100 | connect (s) | 0.35 [0.33–0.37] | 0.06 | 0.06 |
| 100 | fan-out latency p50 (ms) | 33.4 [33.1–33.6] | 5.85 [5.74–5.95] | 6.90 [6.83–6.97] |
| 100 | fan-out latency p99 (ms) | 64.2 [59.3–69.1] | 35.7 [25.0–46.4] | 13.4 [12.2–14.6] |
| 100 | delivered msg/s | 59.3 [59.2–59.4] | 232 [231–234] | 567 [566–569] |
| 500 | ready | 500 | 500 | 500 |
| 500 | connect (s) | 1.27 [1.26–1.27] | 0.35 [0.33–0.37] | 0.21 [0.20–0.21] |
| 500 | fan-out latency p50 (ms) | 74.7 [73.7–75.8] | 29.2 [27.3–31.2] | 14.0 [13.5–14.4] |
| 500 | fan-out latency p99 (ms) | 104 [98.9–108] | 46.0 [42.6–49.5] | 21.0 [18.7–23.2] |
| 500 | delivered msg/s | 17.1 [17.0–17.2] | 83.7 [83.6–83.8] | 180 [179–181] |
| 1000 | ready | 1,000 | 1,000 | 1,000 |
| 1000 | connect (s) | 2.38 [2.35–2.41] | 0.60 | 0.33 [0.32–0.34] |
| 1000 | fan-out latency p50 (ms) | 134 [133–135] | 34.4 [33.2–35.7] | 18.7 [18.1–19.2] |
| 1000 | fan-out latency p99 (ms) | 185 [172–197] | 54.6 [52.9–56.4] | 35.8 [30.8–40.8] |
| 1000 | delivered msg/s | 9.15 [9.10–9.20] | 46.2 [46.1–46.2] | 95.3 [95.3–95.4] |

## Upload (black_hole.jpg, post + thumbnail)

| metric | reference | elixir-official | ours |
|---|---|---|---|
| median total (ms) | 82.9 [81.7–84.1] | 88.5 [86.3–90.8] | 40.9 [39.7–42.0] |
