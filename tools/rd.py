#!/usr/bin/env python3
"""Real-Debrid account helper (standard library only).

Token: set RD_TOKEN, or pass --token-file (a plain token file, or zurg's
config.yml with a `token:` line). Never hardcode it in this file.

Commands:
  status                      account, expiry, library size and health
  list [--status S]           list torrents in the account
  add  ITEMS... [-f FILE]     add magnets / info-hashes you supply
       [--only-cached] [--wait SECONDS] [--all-files] [--dry-run]
  cleanup [--yes]             remove error/dead/virus torrents (dry run without --yes)
  backup [-o FILE]            export the library (hash + name) to JSON
  restore FILE [--only-cached]  re-add everything from a backup
  expiry [--warn-days N]      exit 1 if premium ends within N days (for scripts)

Examples:
  set RD_TOKEN=...            (PowerShell: $env:RD_TOKEN="...")
  python rd.py status
  python rd.py add -f to_add.txt --only-cached
  python rd.py backup -o rd-backup.json
"""

import argparse
import datetime as dt
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.real-debrid.com/rest/1.0"
VIDEO_EXT = (".mkv", ".mp4", ".avi", ".m4v", ".ts", ".m2ts", ".webm", ".mov", ".wmv")
SUB_EXT = (".srt", ".ass", ".ssa", ".sub", ".idx", ".vtt")
SAMPLE_MAX_BYTES = 80 * 1024 * 1024
BAD_STATUSES = {"error", "dead", "virus", "magnet_error"}
HASH_RE = re.compile(r"\b([a-fA-F0-9]{40}|[A-Z2-7]{32})\b")
MAGNET_HASH_RE = re.compile(r"xt=urn:btih:([a-zA-Z0-9]+)", re.I)


# --------------------------------------------------------------------------- API

class RDError(Exception):
    pass


class RD:
    def __init__(self, token):
        self.token = token
        self._last = 0.0

    def _req(self, method, path, data=None, params=None):
        # stay well under RD's 250 requests/minute
        wait = 0.3 - (time.time() - self._last)
        if wait > 0:
            time.sleep(wait)
        url = API + path
        if params:
            url += "?" + urllib.parse.urlencode(params)
        body = urllib.parse.urlencode(data).encode() if data is not None else None
        req = urllib.request.Request(url, data=body, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        for attempt in range(4):
            self._last = time.time()
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    raw = r.read()
                    return json.loads(raw) if raw else None
            except urllib.error.HTTPError as e:
                if e.code == 429 or e.code >= 500:
                    time.sleep(2 ** attempt)
                    continue
                try:
                    detail = json.loads(e.read()).get("error", "")
                except Exception:
                    detail = ""
                raise RDError(f"{method} {path}: HTTP {e.code} {detail}".strip()) from None
            except urllib.error.URLError as e:
                if attempt == 3:
                    raise RDError(f"{method} {path}: {e.reason}") from None
                time.sleep(2 ** attempt)
        raise RDError(f"{method} {path}: gave up after retries")

    def user(self):
        return self._req("GET", "/user")

    def torrents(self):
        out, page = [], 1
        while True:
            batch = self._req("GET", "/torrents", params={"page": page, "limit": 2500}) or []
            out.extend(batch)
            if len(batch) < 2500:
                return out
            page += 1

    def info(self, tid):
        return self._req("GET", f"/torrents/info/{tid}")

    def add_magnet(self, magnet):
        return self._req("POST", "/torrents/addMagnet", data={"magnet": magnet})

    def select_files(self, tid, files):
        return self._req("POST", f"/torrents/selectFiles/{tid}", data={"files": files})

    def delete(self, tid):
        return self._req("DELETE", f"/torrents/delete/{tid}")


# ----------------------------------------------------------------------- helpers

def load_token(token_file):
    if os.environ.get("RD_TOKEN"):
        return os.environ["RD_TOKEN"].strip()
    if token_file:
        text = open(token_file, encoding="utf-8").read()
        m = re.search(r"^\s*token:\s*(\S+)", text, re.M)
        return (m.group(1) if m else text).strip().strip("\"'")
    sys.exit("No token: set RD_TOKEN or use --token-file")


def human(n):
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return f"{n:.1f} {unit}"
        n /= 1024


def normalize_hash(h):
    """Return a lowercase hex info-hash (converts 32-char base32 hashes)."""
    if len(h) == 32:
        import base64
        return base64.b32decode(h.upper()).hex()
    return h.lower()


def parse_items(args_items, file_path):
    """Collect info-hashes from magnets, bare hashes, or a text file (one per line)."""
    raw = list(args_items or [])
    if file_path:
        with open(file_path, encoding="utf-8") as f:
            raw += [line.strip() for line in f if line.strip() and not line.lstrip().startswith("#")]
    seen, out = set(), []
    for item in raw:
        m = MAGNET_HASH_RE.search(item) or HASH_RE.search(item)
        if not m:
            print(f"  skip (no hash found): {item[:80]}")
            continue
        h = normalize_hash(m.group(1))
        if h not in seen:
            seen.add(h)
            out.append((h, item if item.startswith("magnet:") else f"magnet:?xt=urn:btih:{h}"))
    return out


def pick_files(files, all_files):
    if all_files:
        return "all"
    chosen = [
        f for f in files
        if f["path"].lower().endswith(VIDEO_EXT)
        and not ("sample" in f["path"].lower() and f["bytes"] < SAMPLE_MAX_BYTES)
    ]
    if not chosen:
        return "all"
    chosen += [f for f in files if f["path"].lower().endswith(SUB_EXT)]
    return ",".join(str(f["id"]) for f in chosen)


# ---------------------------------------------------------------------- commands

def cmd_status(rd, _):
    u = rd.user()
    exp = u.get("expiration")
    days = (u.get("premium") or 0) / 86400
    print(f"Account : {u.get('username')} ({u.get('type')})")
    print(f"Premium : {days:.1f} days left" + (f" (until {exp[:10]})" if exp else ""))
    ts = rd.torrents()
    by_status = {}
    for t in ts:
        by_status[t["status"]] = by_status.get(t["status"], 0) + 1
    total = sum(t.get("bytes", 0) for t in ts if t["status"] == "downloaded")
    print(f"Library : {len(ts)} torrents, {human(total)} ready")
    for s, n in sorted(by_status.items(), key=lambda x: -x[1]):
        flag = "  <- run `cleanup`" if s in BAD_STATUSES else ""
        print(f"          {s:22} {n}{flag}")


def cmd_list(rd, a):
    ts = rd.torrents()
    if a.status:
        ts = [t for t in ts if t["status"] == a.status]
    for t in sorted(ts, key=lambda t: t.get("added", ""), reverse=True):
        print(f"{t['added'][:10]}  {t['status']:<12} {human(t.get('bytes')):>9}  {t['filename']}")
    print(f"\n{len(ts)} torrents")


def add_one(rd, h, magnet, a, existing):
    if h in existing:
        print(f"  = already in library: {existing[h]}")
        return "exists"
    if a.dry_run:
        print(f"  would add {h}")
        return "dry"
    tid = rd.add_magnet(magnet)["id"]

    # wait for RD to resolve the file list
    deadline = time.time() + 60
    info = rd.info(tid)
    while info["status"] in ("magnet_conversion", "queued") and time.time() < deadline:
        time.sleep(2)
        info = rd.info(tid)
    if info["status"] in BAD_STATUSES:
        rd.delete(tid)
        print(f"  x {info['status']}, removed: {info.get('filename', h)}")
        return "failed"
    if info["status"] == "waiting_files_selection":
        rd.select_files(tid, pick_files(info.get("files", []), a.all_files))

    # cached torrents flip to "downloaded" almost immediately
    deadline = time.time() + a.wait
    info = rd.info(tid)
    while info["status"] != "downloaded" and time.time() < deadline:
        time.sleep(2)
        info = rd.info(tid)

    name = info.get("filename", h)
    if info["status"] == "downloaded":
        print(f"  + ready ({human(info.get('bytes'))}): {name}")
        return "ready"
    if a.only_cached:
        rd.delete(tid)
        print(f"  - not cached ({info['status']} {info.get('progress', 0)}%), removed: {name}")
        return "not_cached"
    print(f"  ~ {info['status']} {info.get('progress', 0)}% (RD keeps downloading): {name}")
    return "pending"


def run_adds(rd, items, a):
    if not items:
        sys.exit("Nothing to add.")
    existing = {t["hash"].lower(): t["filename"] for t in rd.torrents()}
    tally = {}
    for i, (h, magnet) in enumerate(items, 1):
        print(f"[{i}/{len(items)}] {h}")
        try:
            r = add_one(rd, h, magnet, a, existing)
        except RDError as e:
            print(f"  ! {e}")
            r = "error"
        tally[r] = tally.get(r, 0) + 1
        if r == "ready":
            existing[h] = "(just added)"
    print("\nSummary: " + ", ".join(f"{k}={v}" for k, v in sorted(tally.items())))


def cmd_add(rd, a):
    run_adds(rd, parse_items(a.items, a.file), a)


def cmd_restore(rd, a):
    data = json.load(open(a.file, encoding="utf-8"))
    items = [(normalize_hash(t["hash"]), f"magnet:?xt=urn:btih:{t['hash']}") for t in data]
    run_adds(rd, items, a)


def cmd_backup(rd, a):
    ts = rd.torrents()
    data = [{"hash": t["hash"], "filename": t["filename"], "bytes": t.get("bytes"), "added": t.get("added")}
            for t in ts if t["status"] == "downloaded"]
    out = a.output or f"rd-backup-{dt.date.today()}.json"
    with open(out, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=1)
    print(f"Saved {len(data)} torrents to {out}")


def cmd_cleanup(rd, a):
    bad = [t for t in rd.torrents() if t["status"] in BAD_STATUSES]
    if not bad:
        print("Nothing to clean up.")
        return
    for t in bad:
        print(f"  {t['status']:<12} {t['filename']}")
        if a.yes:
            rd.delete(t["id"])
    print(f"\n{'Removed' if a.yes else 'Would remove (use --yes)'}: {len(bad)}")


def cmd_expiry(rd, a):
    days = (rd.user().get("premium") or 0) / 86400
    print(f"{days:.1f} days of premium left")
    sys.exit(1 if days < a.warn_days else 0)


# -------------------------------------------------------------------------- main

def main():
    # Windows consoles default to cp1252, which can't print names like "Kuťáci"
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except AttributeError:
            pass
    p = argparse.ArgumentParser(description="Real-Debrid account helper",
                                formatter_class=argparse.RawDescriptionHelpFormatter, epilog=__doc__)
    p.add_argument("--token-file", help="token file or zurg config.yml")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status")
    sp = sub.add_parser("list"); sp.add_argument("--status")

    def add_opts(sp):
        sp.add_argument("--only-cached", action="store_true", help="remove anything not instantly ready")
        sp.add_argument("--wait", type=int, default=15, help="seconds to wait for 'downloaded' (default 15)")
        sp.add_argument("--all-files", action="store_true", help="select every file, not just video+subs")
        sp.add_argument("--dry-run", action="store_true")

    sp = sub.add_parser("add"); sp.add_argument("items", nargs="*"); sp.add_argument("-f", "--file"); add_opts(sp)
    sp = sub.add_parser("restore"); sp.add_argument("file"); add_opts(sp)
    sp = sub.add_parser("backup"); sp.add_argument("-o", "--output")
    sp = sub.add_parser("cleanup"); sp.add_argument("--yes", action="store_true")
    sp = sub.add_parser("expiry"); sp.add_argument("--warn-days", type=float, default=7)

    a = p.parse_args()
    rd = RD(load_token(a.token_file))
    try:
        {"status": cmd_status, "list": cmd_list, "add": cmd_add, "restore": cmd_restore,
         "backup": cmd_backup, "cleanup": cmd_cleanup, "expiry": cmd_expiry}[a.cmd](rd, a)
    except RDError as e:
        sys.exit(f"Error: {e}")


if __name__ == "__main__":
    main()
