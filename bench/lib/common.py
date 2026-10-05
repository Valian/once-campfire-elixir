"""Shared by bench/run (Docker, macOS) and bench/run-native (bare processes, Linux): the knobs, the
process-model environment, the seed preparation and the three suites driven through bench/loadgen.
"""
import gzip, hashlib, json, math, os, re, sqlite3, sys, time, urllib.request
from datetime import datetime

BENCH = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SEED = os.path.join(BENCH, "seed")
LOADGEN = os.path.join(BENCH, "loadgen", "target", "release", "loadgen")
E = os.environ.get

HTTP_SECS = E("HTTP_SECS", "8")
HTTP_CONCS = E("HTTP_CONCS", "1 16 64").split()
HTTP_GZIP = E("HTTP_GZIP", "1")
if HTTP_GZIP not in ("0", "1"):
    raise SystemExit("HTTP_GZIP must be 0 (identity) or 1 (gzip)")
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


def response_contracts(app, rep, out, routes, cookie, base):
    """Check full read responses against the first app; HTML bytes may differ across ports."""
    path = os.path.join(out, "validation")
    os.makedirs(path, exist_ok=True)
    baseline_path = os.path.join(path, "read-baseline.json")
    baseline = json.load(open(baseline_path)) if os.path.exists(baseline_path) else {}
    responses = {}
    for name, route in routes:
        if route is None:
            continue
        request = urllib.request.Request(base + route, headers={"Cookie": cookie,
                                                               "Accept-Encoding": "gzip" if HTTP_GZIP == "1" else "identity"})
        with urllib.request.urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError(f"{app}: {name} returned {response.status}, expected 200")
            body = response.read()
            encoding = response.headers.get("Content-Encoding", "identity")
        wire_bytes = len(body)
        if encoding == "gzip":
            body = gzip.decompress(body)
        elif encoding != "identity":
            raise RuntimeError(f"{app}: {name} returned unexpected encoding {encoding}")
        if name in ("room_show", "messages_page", "search", "sidebar"):
            attribute = b"data-room-id" if name == "sidebar" else b"data-message-id"
            contract = sorted(set(value.decode() for value in re.findall(attribute + rb'="([0-9]+)"', body)))
            if not contract:
                raise RuntimeError(f"{app}: {name} has no {attribute.decode()} values")
        elif name == "avatar":
            contract = hashlib.sha256(body).hexdigest()
        else:
            if not body:
                raise RuntimeError(f"{app}: {name} has an empty response")
            contract = None  # CSS asset and health-page bytes can legitimately differ.
        if name in baseline and baseline[name] != contract:
            raise RuntimeError(f"{app}: {name} response differs from the first app's content contract")
        baseline[name] = contract
        responses[name] = {"bytes": len(body), "wire_bytes": wire_bytes, "encoding": encoding,
                           "sha256": hashlib.sha256(body).hexdigest(), "contract": contract}
    json.dump(baseline, open(baseline_path, "w"), indent=2)
    json.dump({"app": app, "rep": rep, "responses": responses},
              open(os.path.join(path, f"{app}-{rep}.json"), "w"), indent=2)


def write_counts(db_path, room):
    with sqlite3.connect(f"file:{db_path}?mode=ro", uri=True) as db:
        return (db.execute("SELECT count(*) FROM messages WHERE room_id=?", (room,)).fetchone()[0],
                db.execute("SELECT count(*) FROM message_search_index WHERE body MATCH 'bench write'").fetchone()[0])


def run_suites(app, rep, out, labels, lg, base=BASE, db_path=None):
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
    if "http" in SUITES:
        response_contracts(app, rep, out, routes, cookie, base)
    http = []
    for name, path in routes if "http" in SUITES else []:
        args = ["--post-room", write_room, "--csrf", csrf] if path is None else ["--path", path]
        before_writes = write_counts(db_path, write_room) if path is None and db_path else None
        warmup = lg("http", "--base", base, "--cookie", cookie, *args, "--gzip", HTTP_GZIP, "--conc", 4, "--duration", 2)
        writes = warmup["ok"]
        if warmup["errors"] or set(warmup["statuses"]) != {"200"}:
            raise RuntimeError(f"{app}: {name} warmup failed: {warmup}")
        for c in HTTP_CONCS:
            r = lg("http", "--base", base, "--cookie", cookie, *args, "--gzip", HTTP_GZIP, "--conc", c, "--duration", HTTP_SECS)
            if r["errors"] or set(r["statuses"]) != {"200"}:
                raise RuntimeError(f"{app}: {name} measurement failed: {r}")
            writes += r["ok"]
            r["route"] = name
            http.append(r)
            log(f"{app} rep {rep}: {name} c={c} {r['rps']} rps p50 {r['latency'].get('p50_ms')} "
                f"p99 {r['latency'].get('p99_ms')} {r['statuses']} err {r['errors']}")
        if before_writes is not None:
            after_writes = write_counts(db_path, write_room)
            persisted, indexed = (after - before for before, after in zip(before_writes, after_writes))
            if persisted != writes or indexed != writes:
                raise RuntimeError(f"{app}: expected {writes} writes, persisted {persisted}, indexed {indexed}")
            json.dump({"expected": writes, "persisted": persisted, "indexed": indexed},
                      open(os.path.join(out, "validation", f"{app}-{rep}-writes.json"), "w"), indent=2)

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
