"""Shared by bench/run (Docker, macOS) and bench/run-native (bare processes, Linux): the knobs, the
process-model environment, the seed preparation and the three suites driven through bench/loadgen.
"""
import json, math, os, sqlite3, sys, time
from datetime import datetime

BENCH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(BENCH, "seed")
LOADGEN = os.path.join(BENCH, "loadgen", "target", "release", "loadgen")
E = os.environ.get

HTTP_SECS = E("HTTP_SECS", "8")
HTTP_CONCS = E("HTTP_CONCS", "1 16 64").split()
CABLE_CLIENTS = E("CABLE_CLIENTS", "100 500 1000").split()
CABLE_TPUT_SECS = E("CABLE_TPUT_SECS", "15")
CABLE_POSTERS = E("CABLE_POSTERS", "4")
UPLOAD_REPS = E("UPLOAD_REPS", "5")
PORT = int(E("PORT", "4390"))
SUITES = E("SUITES", "http cable upload").split()
SETTLE_SECS = float(E("SETTLE_SECS", "10"))
EXTRA_ENV = E("EXTRA_ENV", "").split()
BASE = f"http://127.0.0.1:{PORT}"


def log(*a):
    print(f"[{datetime.now():%H:%M:%S}]", *a, file=sys.stderr, flush=True)


def cpuset_size(s):
    return sum(int(b or a) - int(a) + 1 for a, _, b in (part.partition("-") for part in s.split(",")))


def app_env(ncpu):
    """bench/env.reference with the reference's default process model for ncpu cores
    (config/puma.rb: workers = ceil(nproc * 0.666), JOB_CONCURRENCY the same, 5 threads), plus EXTRA_ENV.
    A list of K=V strings."""
    workers = math.ceil(ncpu * 0.666)
    skip = ("WEB_CONCURRENCY=", "JOB_CONCURRENCY=", "RAILS_MAX_THREADS=", "RAILS_LOG_LEVEL=")
    env = [l.strip() for l in open(os.path.join(BENCH, "env.reference"))
           if l.strip() and not l.startswith("#") and not l.startswith(skip)]
    env += [f"WEB_CONCURRENCY={workers}", f"JOB_CONCURRENCY={workers}", "RAILS_MAX_THREADS=5", "RAILS_LOG_LEVEL=warn"]
    return env + EXTRA_ENV


def neuter_deliveries(db_path):
    """Web Push and webhook deliveries to the seed's real endpoints go to a closed local port instead."""
    db = sqlite3.connect(db_path)
    db.execute("UPDATE push_subscriptions SET endpoint = 'https://127.0.0.1:9/push/' || id")
    db.execute("UPDATE webhooks SET url = 'http://127.0.0.1:9/hook/' || id")
    db.commit(); db.close()


def run_suites(app, rep, out, labels, lg, base=BASE):
    """Log in, scrape the busy room, then the HTTP, Action Cable fan-out and upload suites.
    `lg(*args, stderr=None)` runs bench/loadgen and returns its JSON. Returns (http, cable, upload)."""
    L = labels.__getitem__
    room, write_room, before, avatar = L("rooms.watercooler"), L("rooms.hq"), L("messages.busy_060"), L("avatar_tokens.jason")
    cookie = lg("login", "--base", base, "--email", L("emails.david"), "--password", L("passwords.all"))["cookie"]
    scrape = lg("scrape", "--base", base, "--cookie", cookie, "--room", room)
    csrf, streams, css = scrape["csrf"] or "", ",".join(scrape["streams"]), scrape["css"]

    routes = [("room_show", f"/rooms/{room}"), ("messages_page", f"/rooms/{room}/messages?before={before}"),
              ("sidebar", "/users/me/sidebar"), ("search", "/searches?q=coffee"), ("avatar", f"/users/{avatar}/avatar"),
              ("static_css", css), ("up", "/up"), ("post_message", None)]
    http = []
    for name, path in routes if "http" in SUITES else []:
        args = ["--post-room", write_room, "--csrf", csrf] if path is None else ["--path", path]
        lg("http", "--base", base, "--cookie", cookie, *args, "--conc", 4, "--duration", 2)  # warm up
        for c in HTTP_CONCS:
            r = lg("http", "--base", base, "--cookie", cookie, *args, "--conc", c, "--duration", HTTP_SECS)
            r["route"] = name
            http.append(r)
            log(f"{app} rep {rep}: {name} c={c} {r['rps']} rps p50 {r['latency'].get('p50_ms')} "
                f"p99 {r['latency'].get('p99_ms')} {r['statuses']} err {r['errors']}")

    cable = []
    for n in CABLE_CLIENTS if "cable" in SUITES else []:
        with open(os.path.join(out, f".{app}-{rep}-cable{n}.stderr"), "w") as err:
            r = lg("cable", "--base", base, "--cookie", cookie, "--room", room, "--csrf", csrf, "--streams", streams,
                   "--clients", n, "--tput-secs", CABLE_TPUT_SECS, "--posters", CABLE_POSTERS, stderr=err)
        cable.append(r)
        lat, tp = r["latency"]["all_clients"], r["throughput"]
        log(f"{app} rep {rep}: cable {n} clients ready {r['ready']} lat p50 {lat.get('p50_ms')} p99 {lat.get('p99_ms')} "
            f"tput {tp['delivered_msgs_per_sec']} msg/s {tp['complete']}/{tp['posted']}")
        time.sleep(2)

    upload = {}
    if "upload" in SUITES:
        upload = lg("upload", "--base", base, "--cookie", cookie, "--room", write_room, "--csrf", csrf,
                    "--file", os.path.join(BENCH, "black_hole.jpg"), "--reps", UPLOAD_REPS)
        log(f"{app} rep {rep}: upload median {upload['median_total_ms']}ms")
    return http, cable, upload


def load_labels():
    if not os.path.exists(os.path.join(SEED, "db", "production.sqlite3")):
        raise SystemExit("no seed: run bench/make-seed (or copy bench/seed from a machine that has one)")
    return json.load(open(os.path.join(SEED, "labels.json")))


def write_report(out):
    import subprocess
    report = subprocess.run([os.path.join(BENCH, "report"), out], check=True, capture_output=True, text=True).stdout.strip()
    open(os.path.join(out, "report.md"), "w").write(report + "\n")
    print(report)
