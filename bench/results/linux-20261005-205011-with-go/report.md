# Results: linux-20261005-205011-with-go

reference: 2 rep(s), elixir-official: 2 rep(s), go: 2 rep(s), ours: 2 rep(s)

```
date: 2026-10-05T20:50:11.918124
mode: native (bench/run-native), bare processes, loopback
host: g36-1, 7.0.0-38-generic, 12th Gen Intel(R) Core(TM) i5-12500, 12 threads, 62GB, Ubuntu 26.04.1 LTS
governor: powersave 0
server cpus: 4-7 (siblings 4-5 6-7; process model for 4 cpus); loadgen cpus: 8-11 (siblings 10-11 8-9); harness: 0-3
suites: ['http', 'cable', 'upload'] http secs 5 concs ['1', '16', '64'] gzip 1 cable ['100', '500', '1000']
env: WEB_CONCURRENCY=3 JOB_CONCURRENCY=3 RAILS_MAX_THREADS=5 
loadgen: eaa05fc8921b10400f34d78c31e5775e963a32d3 (dirty: 7 files) (bench/loadgen)
redis (external, shared, FLUSHALL per run): redis://127.0.0.1:6379/0 redis 7.4.11
thruster: /home/hermes/Projects/campfire-bench/reference/vendor/bundle/ruby/3.4.0/gems/thruster-0.1.23-x86_64-linux/exe/x86_64-linux/thrust
reference: /home/hermes/Projects/campfire-bench/reference @ 90b330024dec3e757c79b6a7e6568f93da8e3148; ruby 3.4.10 (2026-06-30 revision 2b0b7728dc) +PRISM [x86_64-linux]; jemalloc /usr/lib/x86_64-linux-gnu/libjemalloc.so.2; libvips 8.18.0
go: /home/hermes/orca/workspaces/once-campfire-elixir/server-results/bench/.cache/once-campfire-go @ 8d2f7f24f56dac87dba0211b68b14d9e21e4b516; binary /home/hermes/orca/workspaces/once-campfire-elixir/server-results/bench/.cache/once-campfire-go/.native/bin/campfire sha256 f8ffe1419294abc7bcb57365e983e33098e960ffc670c9e3d1aa5b0dfab91d7e; GOMAXPROCS=4; public front end on 4390, application on 4391; LOG_REQUESTS=true; libvips 8.18.0
go build info:
/home/hermes/orca/workspaces/once-campfire-elixir/server-results/bench/.cache/once-campfire-go/.native/bin/campfire: go1.27.1
	path	github.com/basecamp/once-campfire-go/cmd/campfire
	mod	github.com/basecamp/once-campfire-go	v0.0.0-20261005115018-8d2f7f24f56d	
	dep	github.com/coder/websocket	v1.8.15
	=>	./third_party/websocket	(devel)	
	
	dep	github.com/mattn/go-sqlite3	v1.14.52	h1:wVbm2Qnf4OXkqhBTSPuCRZDRnxfbVrrmiCEroVdog8U=
	dep	golang.org/x/crypto	v0.57.1-0.20260918190515-b4dcfb54b863	h1:3kG0LLrOfvMqZ37MbeJ/uDk5H6tH2L02vx/OcCQ5i2A=
	dep	golang.org/x/net	v0.59.0	h1:5zfYln+w5XCxwrnMMJPufRgNoXEaGxl0wo5GqPXyues=
	dep	golang.org/x/text	v0.42.0	h1:JbOZXgfeCPU9gacVtYliJqOhD+zhrEqK4LfdpmlUZqI=
	build	-buildmode=exe
	build	-compiler=gc
	build	-tags=sqlite_fts5
	build	-trimpath=true
	build	CGO_ENABLED=1
	build	GOARCH=amd64
	build	GOOS=linux
	build	GOAMD64=v1
	build	vcs=git
	build	vcs.revision=8d2f7f24f56dac87dba0211b68b14d9e21e4b516
	build	vcs.time=2026-10-05T11:50:18Z
	build	vcs.modified=false
elixir-official: /home/hermes/Projects/campfire-bench/elixir-official @ b6b82e50a653c4060136bb04e805eb78fd76ba10; release erts-16.4 elixir-1.19.5; ELIXIR_ERL_OPTIONS="+S 4:4 +SDcpu 4:4"; VM under taskset 4-7: schedulers_online=4/4 dirty_cpu_schedulers_online=4 dirty_io_schedulers=10 otp=28 elixir=1.19.5
ours: /home/hermes/orca/workspaces/once-campfire-elixir/server-results @ eaa05fc8921b10400f34d78c31e5775e963a32d3 (dirty: 7 files); release erts-16.4 elixir-1.19.5; ELIXIR_ERL_OPTIONS="+S 4:4 +SDcpu 4:4"; VM under taskset 4-7: schedulers_online=4/4 dirty_cpu_schedulers_online=4 dirty_io_schedulers=10 otp=28 elixir=1.19.5
observed reference rep 1: puma workers 3 (OS threads per worker [12, 12, 13], RAILS_MAX_THREADS 5); resque workers 2; 10 processes: jobs, other, puma, thrust
observed elixir-official rep 1: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 2 processes: beam, thrust
observed go rep 1: 1 processes: go
observed ours rep 1: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
observed ours rep 2: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 1 processes: beam
observed go rep 2: 1 processes: go
observed elixir-official rep 2: beam threads: 4 schedulers, 4 dirty cpu, 10 dirty io; 2 processes: beam, thrust
observed reference rep 2: puma workers 3 (OS threads per worker [12, 13, 12], RAILS_MAX_THREADS 5); resque workers 2; 10 processes: jobs, other, puma, thrust
```

## Startup and memory

| metric | reference | elixir-official | go | ours |
|---|---|---|---|---|
| cold start to /up (ms) | 2,689 [2,688–2,690] | 564 [562–565] | 53.5 [43.0–64.0] | 598 [586–609] |
| idle PSS (MB) | 316 [316–316] | 146 [144–147] | 30.6 [30.5–30.8] | 159 [158–160] |
| peak PSS (MB) | 1,336 [1,302–1,371] | 552 [546–557] | 301 [215–386] | 436 [427–445] |
| idle RSS (MB) | 986 [982–990] | 182 [180–183] | 43.0 [43.0–43.1] | 200 [199–200] |
| peak RSS (MB) | 1,795 [1,762–1,828] | 588 [583–593] | 314 [228–399] | 477 [468–486] |
| external Redis RSS at end (MB) | 18.4 [18.2–18.6] | 36.7 | – | – |

## HTTP (median rps, p50/p99 ms)

| route | conc | reference rps | reference p50 | reference p99 | reference bad | elixir-official rps | elixir-official p50 | elixir-official p99 | elixir-official bad | go rps | go p50 | go p99 | go bad | ours rps | ours p50 | ours p99 | ours bad |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| room_show | 1 | 70.6 [69.8–71.4] | 13.7 | 23.6 | 0 | 229 [225–233] | 4.34 | 4.82 | 0 | 692 [691–693] | 1.41 | 2.22 | 0 | 489 [486–492] | 2.03 | 2.32 | 0 |
| room_show | 16 | 143 [142–145] | 110 | 268 | 0 | 472 [471–473] | 33.6 | 44.7 | 0 | 1,732 [1,731–1,732] | 6.82 | 38.4 | 0 | 1,210 [1,202–1,217] | 13.0 | 18.5 | 0 |
| room_show | 64 | 134 | 462 | 604 | 0 | 469 [469–470] | 135 | 156 | 0 | 1,721 [1,718–1,724] | 34.9 | 95.2 | 0 | 1,182 [1,178–1,186] | 53.8 | 60.6 | 0 |
| messages_page | 1 | 129 [126–132] | 7.40 | 14.4 | 0 | 312 [311–313] | 3.19 | 3.51 | 0 | 928 [928–929] | 1.05 | 1.81 | 0 | 630 [623–638] | 1.57 | 1.85 | 0 |
| messages_page | 16 | 272 [267–276] | 56.6 | 128 | 0 | 636 [634–639] | 24.9 | 37.3 | 0 | 2,235 [2,232–2,237] | 5.45 | 25.3 | 0 | 1,481 [1,465–1,497] | 10.7 | 15.5 | 0 |
| messages_page | 64 | 261 [260–262] | 244 | 308 | 0 | 630 [629–631] | 101 | 119 | 0 | 2,226 [2,225–2,227] | 26.0 | 85.7 | 0 | 1,440 [1,424–1,456] | 44.2 | 51.2 | 0 |
| sidebar | 1 | 181 [180–182] | 5.40 | 7.04 | 0 | 606 [604–608] | 1.63 | 1.97 | 0 | 2,846 [2,837–2,854] | 0.34 | 0.74 | 0 | 1,114 [1,082–1,145] | 0.89 | 1.08 | 0 |
| sidebar | 16 | 369 [368–371] | 42.7 | 70.1 | 0 | 794 [779–809] | 20.0 | 25.7 | 0 | 8,378 [8,268–8,488] | 1.57 | 5.99 | 0 | 2,374 [2,350–2,399] | 6.70 | 8.87 | 0 |
| sidebar | 64 | 358 [346–370] | 179 | 236 | 0 | 831 [827–835] | 77.2 | 86.1 | 0 | 8,806 [8,715–8,897] | 6.99 | 13.7 | 0 | 2,197 [2,164–2,231] | 29.1 | 32.6 | 0 |
| search | 1 | 132 [131–133] | 7.46 | 9.08 | 0 | 450 [447–453] | 2.21 | 2.51 | 0 | 1,170 [1,170–1,171] | 0.83 | 1.49 | 0 | 763 [752–775] | 1.32 | 1.47 | 0 |
| search | 16 | 272 [271–273] | 57.3 | 109 | 0 | 767 [762–772] | 20.8 | 25.8 | 0 | 3,078 [3,074–3,081] | 3.89 | 16.6 | 0 | 1,642 [1,494–1,790] | 9.73 | 12.6 | 0 |
| search | 64 | 264 [257–272] | 237 | 303 | 0 | 775 [772–777] | 82.4 | 92.4 | 0 | 3,082 [3,081–3,084] | 19.6 | 46.4 | 0 | 1,703 [1,661–1,744] | 37.5 | 42.0 | 0 |
| avatar | 1 | 18,035 [17,964–18,106] | 0.05 | 0.17 | 0 | 18,842 [18,780–18,905] | 0.05 | 0.15 | 0 | 28,012 [27,769–28,256] | 0.03 | 0.08 | 0 | 16,170 [15,828–16,513] | 0.06 | 0.08 | 0 |
| avatar | 16 | 51,694 [51,271–52,117] | 0.22 | 1.30 | 0 | 52,967 [52,466–53,468] | 0.21 | 1.34 | 0 | 102,544 [101,769–103,320] | 0.12 | 0.69 | 0 | 37,147 [37,130–37,164] | 0.43 | 0.60 | 0 |
| avatar | 64 | 41,403 [41,300–41,506] | 0.81 | 8.65 | 0 | 42,649 [42,425–42,873] | 0.74 | 8.74 | 0 | 102,177 [101,320–103,034] | 0.45 | 3.02 | 0 | 37,417 [37,317–37,517] | 1.70 | 1.89 | 0 |
| static_css | 1 | 23,181 [23,037–23,324] | 0.04 | 0.10 | 0 | 23,055 [23,039–23,071] | 0.04 | 0.10 | 0 | 38,226 [38,123–38,329] | 0.02 | 0.04 | 0 | 31,332 [31,327–31,336] | 0.03 | 0.04 | 0 |
| static_css | 16 | 66,540 [66,205–66,876] | 0.18 | 1.01 | 0 | 66,235 [66,123–66,346] | 0.18 | 1.04 | 0 | 142,373 [142,356–142,390] | 0.09 | 0.41 | 0 | 89,831 [89,669–89,993] | 0.18 | 0.25 | 0 |
| static_css | 64 | 56,724 [56,644–56,804] | 0.70 | 5.77 | 0 | 56,212 [55,984–56,440] | 0.68 | 6.03 | 0 | 145,420 [145,211–145,629] | 0.30 | 2.11 | 0 | 88,324 [88,316–88,333] | 0.72 | 0.80 | 0 |
| up | 1 | 1,435 [1,430–1,439] | 0.67 | 1.19 | 0 | 2,559 [2,549–2,568] | 0.38 | 0.55 | 0 | 22,349 [22,286–22,412] | 0.04 | 0.09 | 0 | 31,510 [31,048–31,972] | 0.03 | 0.04 | 0 |
| up | 16 | 2,896 [2,896–2,896] | 5.38 | 10.3 | 0 | 4,869 [4,857–4,881] | 3.17 | 7.54 | 0 | 75,610 [75,554–75,666] | 0.17 | 0.87 | 0 | 80,496 [79,935–81,056] | 0.20 | 0.25 | 0 |
| up | 64 | 2,860 [2,854–2,866] | 22.1 | 33.2 | 0 | 5,094 [5,075–5,113] | 11.8 | 27.5 | 0 | 75,568 [75,514–75,622] | 0.63 | 3.61 | 0 | 79,934 [79,476–80,391] | 0.80 | 0.90 | 0 |
| post_message | 1 | 107 [106–107] | 8.29 | 32.4 | 0 | 265 [264–266] | 3.44 | 16.1 | 0 | 749 [722–777] | 0.74 | 16.0 | 0 | 712 [688–735] | 1.20 | 3.44 | 0 |
| post_message | 16 | 166 [164–169] | 89.0 | 239 | 0 | 462 [459–464] | 30.6 | 56.9 | 0 | 1,482 [1,466–1,499] | 4.45 | 42.3 | 0 | 987 [984–990] | 13.4 | 60.6 | 0 |
| post_message | 64 | 163 [162–164] | 350 | 637 | 0 | 498 [495–501] | 129 | 144 | 0 | 1,481 [1,481–1,481] | 35.3 | 195 | 0 | 953 [953–954] | 56.9 | 120 | 0 |

## Action Cable fan-out

| clients | metric | reference | elixir-official | go | ours |
|---|---|---|---|---|---|
| 100 | ready | 100 | 100 | 100 | 100 |
| 100 | connect (s) | 0.35 [0.33–0.38] | 0.08 [0.06–0.11] | 0.07 [0.06–0.08] | 0.07 [0.06–0.07] |
| 100 | fan-out latency p50 (ms) | 29.6 [28.0–31.1] | 5.97 [5.90–6.04] | 6.29 [6.25–6.33] | 6.83 [6.81–6.86] |
| 100 | fan-out latency p99 (ms) | 61.5 [59.5–63.4] | 28.2 [17.3–39.1] | 8.39 [7.59–9.20] | 11.4 [10.6–12.3] |
| 100 | delivered msg/s | 60.3 [58.3–62.3] | 238 [237–238] | 698 [697–698] | 586 [585–586] |
| 500 | ready | 500 | 500 | 500 | 500 |
| 500 | connect (s) | 1.04 [1.01–1.06] | 0.33 [0.31–0.36] | 0.15 [0.12–0.17] | 0.21 |
| 500 | fan-out latency p50 (ms) | 72.4 [71.4–73.3] | 18.1 [17.2–19.0] | 10.1 [9.95–10.2] | 10.6 [9.90–11.2] |
| 500 | fan-out latency p99 (ms) | 139 [135–144] | 54.2 [47.5–60.9] | 26.9 [26.5–27.3] | 18.7 [16.7–20.8] |
| 500 | delivered msg/s | 17.5 [17.3–17.6] | 86.2 [85.7–86.6] | 288 [285–291] | 188 [188–188] |
| 1000 | ready | 1,000 | 1,000 | 1,000 | 1,000 |
| 1000 | connect (s) | 1.92 [1.90–1.95] | 0.55 [0.54–0.57] | 0.20 [0.19–0.20] | 0.35 [0.33–0.38] |
| 1000 | fan-out latency p50 (ms) | 130 [128–133] | 26.9 [25.5–28.4] | 14.2 [14.0–14.3] | 15.0 [14.0–16.0] |
| 1000 | fan-out latency p99 (ms) | 245 [239–251] | 61.2 [57.7–64.6] | 42.3 [36.4–48.2] | 53.6 [33.6–73.6] |
| 1000 | delivered msg/s | 9.35 [9.30–9.40] | 47.0 [47.0–47.1] | 159 [158–160] | 99.5 [99.0–100] |

## Upload (black_hole.jpg, post + thumbnail)

| metric | reference | elixir-official | go | ours |
|---|---|---|---|---|
| median total (ms) | 69.8 [68.9–70.8] | 88.2 [88.1–88.4] | 38.6 | 41.2 [40.4–42.1] |
