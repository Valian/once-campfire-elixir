# Handoff: finish the perf pass and run the native Linux benchmark

You are continuing work started on a laptop. The project is an idiomatic Phoenix
reimplementation of ONCE Campfire. Its goal is to show what normal, clean Elixir achieves on
DHH's Campfire benchmark, compared with Rails and the official Elixir port
(basecamp/once-campfire-elixir, a Rails transliteration). Read README.md, docs/SPEC.md (skim),
docs/ARCHITECTURE.md, bench/README.md and AGENTS.md first.

Principles: idiomatic and simple, with no benchmark-special hacks (no per-user page caching,
no skipped work, no HTML contract changes). Measure before and after every change.

## State of the branches (origin = github.com/Valian/once-campfire-elixir)

- `main`: the merged app and the macOS/Docker harness (`bench/run`).
- `perf-wip`: an unfinished perf pass (from main):
  - `CampfireWeb.Gzip` (level 3 gzip plug)
  - `CampfireWeb.AssetCache` (digested CSS/JS from `:persistent_term`)
  - the scheduler busy-wait revert in `rel/vm.args.eex`
  - `bench/PERF.md`
  It was never measured end to end.
- `linux-native-bench` (this branch): `bench/run-native`, `bench/setup-native` and
  `bench/lib/common.py`, a native Linux harness that runs each app as a bare process pinned
  with taskset. Setup on this server was done: the apps are built under
  `~/Projects/campfire-bench/{reference,elixir-official}` and in this repo, with toolchains via
  mise, apt libs installed, and Redis as a Docker container on 127.0.0.1:6379 (started by
  grupa36; you can't run Docker as hermes, so don't try). The smoke run had not been done yet.

## Tasks

1. Create a branch `server-results` from `main`, then merge `perf-wip` and `linux-native-bench`.
2. Finish the perf pass, using the review notes:
   a. **Gzip plug.** Check whether the Bandit version in mix.lock lets you configure the gzip
      level through config (`http_options` / `deflate_options` or similar).
      - If it does, delete `CampfireWeb.Gzip` and use config.
      - If it doesn't, keep a minimal plug: a simple Accept-Encoding check, and no q-value or
        zstd logic unless Bandit really negotiates zstd for our clients.
      Record the result in PERF.md, including whether upstreaming a level option to Bandit
      would be the right fix.
   b. **AssetCache.** Keep it small, and make sure dev still serves changed assets.
   c. **Writer path.** POST message used about 3.6 ms of writer occupancy; the target is well
      under 1 ms. Profile it and fix it idiomatically: keep only the writes inside the
      transaction, use single statements, and render and broadcast outside the transaction.
   d. **Cable resets.** If time permits, check whether the cable "connection reset" failures
      (500–1000 clients) reproduce natively on Linux. They were seen behind Docker Desktop's
      port forwarder.
   Then `mix precommit` must be green (`SEED_DIR=<path to seed>`).
3. **Native benchmark, three apps.** Run `reference`, `elixir-official` and `ours` with
   `bench/run-native`. Use taskset for all apps. For both Elixir apps, also pass explicit
   `+S 4:4 +SDcpu 4:4`, and record the actual schedulers_online and dirty_cpu_schedulers_online
   in env.txt, along with the Puma worker/thread and Resque counts for Rails.
   a. Smoke run: `HTTP_SECS=3 HTTP_CONCS=16 CABLE_CLIENTS=100`, 1 rep. All routes must return
      200 with zero errors; cable must be ready; upload must work.
   b. Full run: 2 reps, `HTTP_SECS=5`, concurrencies 1/16/64, cable 100/500/1000. Before
      running, report the load average, and don't kill other people's processes.
   c. Put the results under `bench/results/linux-<timestamp>/`.
4. **README.** Update the results section with the Linux numbers as the primary table, and keep
   the macOS table as a secondary one. State the host, the CPU pinning, the commits and any
   process-model deviations.
5. **Commit and open a PR.** Commit in logical commits, each ending with
   `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Push `server-results`
   and open a PR to main with `gh` (if auth is available) containing a summary: the findings
   table (issue → root cause → fix → before/after) and the comparison table. Do NOT merge to
   main yourself. Leave no app processes running when you're done.

If GitHub push auth isn't available as hermes, commit locally and leave a
`RESULTS-SUMMARY.md` at the repo root describing everything above.
