#!/usr/bin/env python3
"""debrid-plex-stack management page (LAN only). Python standard library only.

    python app.py serve     run the web server (inside the debrid-admin container)
    python app.py hash      read a password on stdin, print its hash (used by the installer)

The page never touches Docker or the stack's secrets. It reads the status the host
agent publishes in /data/state, and queues whitelisted requests in /data/requests,
which the host agent (scripts/agent.sh) validates and applies within a minute.
"""

import base64
import hashlib
import hmac
import html
import http.cookies
import json
import os
import re
import secrets
import ssl
import sys
import threading
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

DATA = Path(os.environ.get("ADMIN_DATA", "/data"))
REQUESTS, STATE, AUTH = DATA / "requests", DATA / "state", DATA / "auth"
PORT = int(os.environ.get("ADMIN_PORT", "8099"))

SESSION_IDLE = 30 * 60          # seconds of inactivity before logout
MAX_FAILS, LOCK_SECS = 5, 15 * 60
PBKDF2_ITER = 600_000
KEY_RE = re.compile(r"^[A-Za-z0-9_-]{20,100}$")
BACKUP_RE = re.compile(r"^[a-z]+-[0-9-]+\.json$")

sessions = {}                   # token -> {"csrf": str, "seen": float}
fails = []                      # timestamps of failed logins (global: LAN clients can share one NAT address)
lock = threading.Lock()


# ------------------------------------------------------------------ passwords

def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, PBKDF2_ITER)
    return f"pbkdf2_sha256${PBKDF2_ITER}${base64.b64encode(salt).decode()}${base64.b64encode(dk).decode()}"


def check_password(password: str) -> bool:
    try:
        _, iters, salt, dk = (AUTH / "password.hash").read_text().strip().split("$")
        calc = hashlib.pbkdf2_hmac("sha256", password.encode(), base64.b64decode(salt), int(iters))
        return hmac.compare_digest(calc, base64.b64decode(dk))
    except (OSError, ValueError):
        return False


# ---------------------------------------------------------------------- state

def read_json(name):
    try:
        return json.loads((STATE / name).read_text())
    except (OSError, ValueError):
        return {}


def read_text(name, default=""):
    try:
        return (STATE / name).read_text()
    except OSError:
        return default


def queue(action: str, value: str = "") -> None:
    rid = f"{int(time.time())}-{secrets.token_hex(4)}"
    tmp = REQUESTS / f".{rid}.tmp"
    tmp.write_text(f"action={action}\nvalue={value}\n")
    os.chmod(tmp, 0o600)
    tmp.rename(REQUESTS / f"{rid}.req")


def pending() -> int:
    return len(list(REQUESTS.glob("*.req")))


# ----------------------------------------------------------------------- html

CSS = """
:root{--bg:#f6f7f9;--card:#fff;--fg:#1d2330;--muted:#667085;--line:#e4e7ec;--ok:#12805c;--bad:#c4320a;--acc:#2f5bd3}
@media (prefers-color-scheme:dark){:root{--bg:#0f1218;--card:#171b23;--fg:#e6e9ef;--muted:#98a2b3;--line:#2a303c;--ok:#3ccf91;--bad:#ff7a59;--acc:#7aa2ff}}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:860px;margin:0 auto;padding:16px}header{display:flex;justify-content:space-between;align-items:center;gap:8px;flex-wrap:wrap}
h1{font-size:20px;margin:8px 0}h2{font-size:16px;margin:0 0 10px}nav a{margin-right:12px;color:var(--acc);text-decoration:none}
.card{background:var(--card);border:1px solid var(--line);border-radius:10px;padding:16px;margin:14px 0}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(170px,1fr));gap:10px}
.stat{border:1px solid var(--line);border-radius:8px;padding:10px}.stat b{display:block;font-size:18px}
.muted{color:var(--muted)}.ok{color:var(--ok)}.bad{color:var(--bad)}
input,select,button{font:inherit;padding:8px 10px;border-radius:8px;border:1px solid var(--line);background:var(--bg);color:var(--fg)}
input,select{width:100%}button{background:var(--acc);color:#fff;border:0;cursor:pointer}button.secondary{background:transparent;color:var(--acc);border:1px solid var(--acc)}
form.inline{display:inline-block;margin:4px 6px 4px 0}label{display:block;margin:10px 0 4px}
.row{display:flex;gap:8px;align-items:end}.row>*:first-child{flex:1}
pre{white-space:pre-wrap;word-break:break-all;font-size:12.5px;max-height:480px;overflow:auto}
table{width:100%;border-collapse:collapse;font-size:14px}td{padding:4px 6px;border-top:1px solid var(--line);vertical-align:top}
.flash{border-left:4px solid var(--acc)}
"""


def page(title, body, session=None, flash=""):
    nav = ""
    if session:
        nav = ('<nav><a href="/">Status</a><a href="/keys">Keys &amp; provider</a><a href="/backups">Backups</a>'
               '<a href="/log">Log</a></nav>'
               f'<form class="inline" method="post" action="/logout">{csrf_field(session)}'
               '<button class="secondary">Log out</button></form>')
    fl = f'<div class="card flash">{html.escape(flash)}</div>' if flash else ""
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{html.escape(title)} · debrid</title><style>{CSS}</style></head><body><main>'
            f'<header><h1>debrid-plex-stack</h1>{nav}</header>{fl}{body}</main></body></html>')


def csrf_field(session):
    return f'<input type="hidden" name="csrf" value="{session["csrf"]}">'


def button(session, action, label, value="", secondary=False, confirm=""):
    cls = ' class="secondary"' if secondary else ""
    return (f'<form class="inline" method="post" action="/action">{csrf_field(session)}'
            f'<input type="hidden" name="action" value="{action}"><input type="hidden" name="value" value="{value}">'
            f'<button{cls}>{html.escape(label)}</button></form>')


def results_table(limit=8):
    rows = []
    for line in reversed(read_text("results.log").strip().splitlines()[-limit:]):
        parts = line.split("\t")
        if len(parts) == 4:
            when, action, status, msg = (html.escape(p) for p in parts)
            cls = "ok" if status == "OK" else "bad"
            rows.append(f'<tr><td class="muted">{when}</td><td>{action}</td><td class="{cls}">{status}</td><td>{msg}</td></tr>')
    return "<table>" + "".join(rows) + "</table>" if rows else '<p class="muted">No actions yet.</p>'


def status_body(session):
    s = read_json("status.json")
    if not s:
        return '<div class="card"><p class="bad">No status yet. The host agent publishes it every minute; check that the watchdog task is running.</p></div>'
    e = html.escape
    containers = "".join(
        f'<div class="stat"><span class="muted">{e(name)}</span><b class="{"ok" if st.startswith("running") and "unhealthy" not in st else "bad"}">{e(st)}</b></div>'
        for name, st in s.get("containers", {}).items())
    items = " · ".join(f"{e(k)}: {v}" for k, v in s.get("items", {}).items())
    acct = s.get("account", {})
    if acct.get("ok"):
        acct_txt = (f'{acct["days_left"]} days left' if "days_left" in acct else "active") + (f' (until {e(acct.get("expires", ""))})' if acct.get("expires") else "")
    else:
        acct_txt = '<span class="bad">could not check</span>'
    mem = s.get("dockerd_mb", 0)
    maint = s.get("maintenance")
    return f"""
<div class="card"><h2>Overview</h2><div class="grid">
<div class="stat"><span class="muted">Provider</span><b>{e(s.get("provider", "?"))}</b></div>
<div class="stat"><span class="muted">Account</span><b>{acct_txt}</b></div>
<div class="stat"><span class="muted">Mount</span><b class="{"ok" if s.get("mount_ok") else "bad"}">{"OK" if s.get("mount_ok") else "down"}</b></div>
<div class="stat"><span class="muted">Docker memory</span><b class="{"bad" if mem > 2048 else ""}">{mem} MB</b></div>
</div><p class="muted">Library: {items or "–"} · key ending …{e(s.get("key_hint", "") or "?")} · updated {e(s.get("updated", ""))}</p></div>
<div class="card"><h2>Containers</h2><div class="grid">{containers}</div></div>
<div class="card"><h2>Actions</h2>
{button(session, "restart", "Restart stack")}
{button(session, "maintenance_off" if maint else "maintenance_on", "Resume watchdog" if maint else "Pause watchdog (maintenance)", secondary=True)}
{button(session, "plex_setup", "Re-apply Plex settings", secondary=True)}
<p class="muted">Actions are applied by the host within a minute. Pending: {pending()}.</p></div>
<div class="card"><h2>Recent actions</h2>{results_table()}</div>"""


def keys_body(session):
    s = read_json("status.json")
    cur = s.get("provider", "realdebrid")
    other = "torbox" if cur == "realdebrid" else "realdebrid"
    names = {"realdebrid": "Real-Debrid", "torbox": "TorBox (experimental)"}
    other_set = s.get("torbox_key_set") if other == "torbox" else s.get("rd_key_set")
    switch = (button(session, "switch_provider", f"Switch to {names[other]}", other, secondary=True)
              if other_set else f'<p class="muted">Save a {names[other]} key first to enable switching.</p>')
    return f"""
<div class="card"><h2>Real-Debrid API key</h2>
<p class="muted">From <a href="https://real-debrid.com/apitoken" rel="noreferrer">real-debrid.com/apitoken</a>. Checked with Real-Debrid before it's saved; saved keys are never shown here.</p>
<form method="post" action="/action" class="row">{csrf_field(session)}<input type="hidden" name="action" value="set_rd_token">
<div><label for="rd">New key</label><input id="rd" name="value" type="password" autocomplete="off" required></div><button>Save</button></form></div>
<div class="card"><h2>TorBox API key</h2>
<p class="muted">From <a href="https://torbox.app/settings" rel="noreferrer">torbox.app/settings</a>.</p>
<form method="post" action="/action" class="row">{csrf_field(session)}<input type="hidden" name="action" value="set_torbox_key">
<div><label for="tb">New key</label><input id="tb" name="value" type="password" autocomplete="off" required></div><button>Save</button></form></div>
<div class="card"><h2>Provider</h2><p>Currently using <b>{html.escape(names.get(cur, cur))}</b>.</p>
<p class="muted">Switching stops the stack for a minute. Back up your library first; the new provider has its own library.</p>{switch}</div>
<div class="card"><h2>Recent actions</h2>{results_table()}</div>"""


def backups_body(session):
    files = sorted((p for p in (STATE / "backups").glob("*.json") if BACKUP_RE.match(p.name)), reverse=True)
    rows = "".join(f'<tr><td><a href="/backups/{p.name}">{p.name}</a></td><td class="muted">{p.stat().st_size // 1024} KB</td></tr>' for p in files)
    return f"""<div class="card"><h2>Library backups</h2>
<p class="muted">A list of the items in your debrid library (hashes and names), to re-add them after a lapse or at another provider. The newest 10 are kept.</p>
{button(session, "backup", "Make a backup now")}
{"<table>" + rows + "</table>" if rows else '<p class="muted">No backups yet.</p>'}</div>"""


def log_body(_session):
    return f'<div class="card"><h2>Stack log</h2><pre>{html.escape(read_text("log.txt", "No log yet."))}</pre></div>'


# -------------------------------------------------------------------- server

class Handler(BaseHTTPRequestHandler):
    server_version = "debrid-admin"
    sys_version = ""

    def log_message(self, fmt, *args):  # no request logging (would include paths only, but keep it quiet)
        pass

    # --- helpers
    def send(self, code, body="", ctype="text/html; charset=utf-8", headers=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Frame-Options", "DENY")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'")
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(data)

    def redirect(self, to, headers=None):
        self.send(303, "", headers={"Location": to, **(headers or {})})

    def session(self):
        cookie = http.cookies.SimpleCookie(self.headers.get("Cookie", ""))
        token = cookie["sid"].value if "sid" in cookie else ""
        with lock:
            s = sessions.get(token)
            if s and time.time() - s["seen"] < SESSION_IDLE:
                s["seen"] = time.time()
                return token, s
            sessions.pop(token, None)
        return "", None

    def form(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length > 4096:
            return {}
        raw = self.rfile.read(length).decode(errors="replace")
        return {k: v[0] for k, v in urllib.parse.parse_qs(raw).items()}

    def cookie(self, value, max_age):
        secure = "; Secure" if self.server.tls else ""
        return f"sid={value}; HttpOnly; SameSite=Strict; Path=/; Max-Age={max_age}{secure}"

    # --- routes
    def do_GET(self):
        path = urllib.parse.urlsplit(self.path).path
        if path == "/healthz":
            return self.send(200, "ok", "text/plain")
        token, s = self.session()
        if not s:
            if path == "/login":
                return self.send(200, login_page())
            return self.redirect("/login")
        flash = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("m", [""])[0][:200]
        if path == "/":
            return self.send(200, page("Status", status_body(s), s, flash))
        if path == "/keys":
            return self.send(200, page("Keys", keys_body(s), s, flash))
        if path == "/backups":
            return self.send(200, page("Backups", backups_body(s), s, flash))
        if path.startswith("/backups/"):
            name = path.rsplit("/", 1)[1]
            f = STATE / "backups" / name
            if BACKUP_RE.match(name) and f.is_file():
                return self.send(200, f.read_bytes(), "application/json",
                                 {"Content-Disposition": f'attachment; filename="{name}"'})
            return self.send(404, page("Not found", "<p>Not found.</p>", s))
        if path == "/log":
            return self.send(200, page("Log", log_body(s), s))
        return self.send(404, page("Not found", "<p>Not found.</p>", s))

    do_HEAD = do_GET

    def do_POST(self):
        path = urllib.parse.urlsplit(self.path).path
        f = self.form()
        if path == "/login":
            return self.login(f)
        token, s = self.session()
        if not s or not hmac.compare_digest(f.get("csrf", ""), s["csrf"]):
            return self.redirect("/login")
        if path == "/logout":
            with lock:
                sessions.pop(token, None)
            return self.redirect("/login", {"Set-Cookie": self.cookie("", 0)})
        if path == "/action":
            return self.action(f)
        return self.send(404, page("Not found", "<p>Not found.</p>", s))

    def login(self, f):
        now = time.time()
        with lock:
            fails[:] = [t for t in fails if now - t < LOCK_SECS]
            locked = len(fails) >= MAX_FAILS
        if locked:
            return self.send(429, login_page("Too many failed attempts. Try again in 15 minutes."))
        if check_password(f.get("password", "")):
            token = secrets.token_urlsafe(32)
            with lock:
                fails.clear()
                sessions[token] = {"csrf": secrets.token_urlsafe(32), "seen": now}
            return self.redirect("/", {"Set-Cookie": self.cookie(token, SESSION_IDLE)})
        with lock:
            fails.append(now)
        time.sleep(1)
        return self.send(401, login_page("Wrong password."))

    def action(self, f):
        action, value = f.get("action", ""), f.get("value", "").strip()
        back = "/keys" if action in ("set_rd_token", "set_torbox_key", "switch_provider") else "/"
        if action == "backup":
            back = "/backups"
        if action in ("set_rd_token", "set_torbox_key"):
            if not KEY_RE.match(value):
                return self.redirect(back + "?m=" + urllib.parse.quote("That doesn't look like an API key (20-100 letters, digits, - or _)."))
        elif action == "switch_provider":
            if value not in ("realdebrid", "torbox"):
                return self.redirect(back)
        elif action in ("restart", "maintenance_on", "maintenance_off", "plex_setup", "backup"):
            value = ""
        else:
            return self.redirect("/")
        queue(action, value)
        return self.redirect(back + "?m=" + urllib.parse.quote("Queued. The host applies it within a minute; refresh to see the result."))


def login_page(msg=""):
    m = f'<p class="bad">{html.escape(msg)}</p>' if msg else ""
    return page("Log in", f"""<div class="card" style="max-width:380px;margin:40px auto">
<h2>Log in</h2>{m}<form method="post" action="/login">
<label for="pw">Password</label><input id="pw" name="password" type="password" autocomplete="current-password" autofocus required>
<p><button>Log in</button></p></form><p class="muted">Only reachable from your home network.</p></div>""")


class Server(ThreadingHTTPServer):
    daemon_threads = True
    ssl_ctx = None

    @property
    def tls(self):
        return self.ssl_ctx is not None

    def finish_request(self, request, client_address):
        # TLS handshake per connection in the worker thread, so a slow or plain-HTTP
        # client can't block the accept loop
        request.settimeout(30)
        if self.ssl_ctx:
            try:
                request = self.ssl_ctx.wrap_socket(request, server_side=True)
            except (ssl.SSLError, OSError):
                return
        super().finish_request(request, client_address)


def serve():
    for d in (REQUESTS, STATE):
        d.mkdir(parents=True, exist_ok=True)
    if not (AUTH / "password.hash").exists():
        sys.exit("no password set: run the installer or scripts/admin-password.sh")
    httpd = Server(("0.0.0.0", PORT), Handler)
    cert, key = AUTH / "cert.pem", AUTH / "key.pem"
    if cert.exists() and key.exists():
        ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ctx.minimum_version = ssl.TLSVersion.TLSv1_2
        ctx.load_cert_chain(cert, key)
        httpd.ssl_ctx = ctx
    print(f"debrid-admin listening on :{PORT} ({'https' if httpd.tls else 'http'})", flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "serve"
    if cmd == "hash":
        pw = sys.stdin.readline().rstrip("\n")
        if len(pw) < 8:
            sys.exit("password must be at least 8 characters")
        print(hash_password(pw))
    elif cmd == "serve":
        serve()
    else:
        sys.exit(__doc__)
