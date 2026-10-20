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
import socket
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
REMEMBER_IDLE = 30 * 24 * 3600  # "keep me signed in" (the phone with the power switch)
SAFE_NEXT = ("/power",)         # pages a login may return to
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


def save_password(password: str) -> None:
    tmp = AUTH / ".password.hash.tmp"
    tmp.write_text(hash_password(password) + "\n")
    os.chmod(tmp, 0o600)
    os.replace(tmp, AUTH / "password.hash")       # atomic: a crash never leaves a half-written hash


def locked_out() -> bool:
    now = time.time()
    with lock:
        fails[:] = [t for t in fails if now - t < LOCK_SECS]
        return len(fails) >= MAX_FAILS


def record_fail() -> None:
    with lock:
        fails.append(time.time())
    time.sleep(1)


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
:root{--bg:#f6f7f9;--card:#fff;--fg:#1d2330;--muted:#667085;--line:#e4e7ec;--ok:#12805c;--bad:#c4320a;--acc:#2f5bd3;--warn:#b54708}
@media (prefers-color-scheme:dark){:root{--bg:#0f1218;--card:#171b23;--fg:#e6e9ef;--muted:#98a2b3;--line:#2a303c;--ok:#3ccf91;--bad:#ff7a59;--acc:#7aa2ff;--warn:#f79009}}
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
.banner{border-left:6px solid var(--warn);background:color-mix(in srgb,var(--warn) 12%,var(--card))}
.banner.expired{--warn:var(--bad)}.banner a{margin-left:6px;color:var(--acc)}
code{font:13px ui-monospace,monospace;background:var(--bg);padding:2px 6px;border-radius:6px}
input[readonly]{font:13px ui-monospace,monospace}
"""


def page(title, body, session=None, flash=""):
    nav = ""
    if session:
        nav = ('<nav><a href="/">Status</a><a href="/keys">Keys &amp; provider</a><a href="/backups">Backups</a>'
               '<a href="/log">Log</a><a href="/password">Password</a></nav>'
               f'<form class="inline" method="post" action="/logout">{csrf_field(session)}'
               '<button class="secondary">Log out</button></form>')
    fl = f'<div class="card flash">{html.escape(flash)}</div>' if flash else ""
    if session:
        fl = expiry_banner() + fl
    return (f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>{html.escape(title)} · debrid</title><style>{CSS}</style></head><body><main>'
            f'<header><h1>debrid-plex-stack</h1>{nav}</header>{fl}{body}</main></body></html>')


RENEW_LINKS = {
    "realdebrid": ("Real-Debrid", "https://real-debrid.com/premium"),
    "torbox": ("TorBox", "https://torbox.app/pricing"),
}


def expiry_banner():
    """Warning bar on every page when premium is about to run out (or has)."""
    st = read_json("status.json")
    acct = st.get("account") or {}
    days = acct.get("days_left")
    warn = st.get("expiry_warn_days", 7)
    if not acct.get("ok") or not isinstance(days, int) or not isinstance(warn, int) or days > warn:
        return ""
    name, url = RENEW_LINKS.get(st.get("provider"), RENEW_LINKS["realdebrid"])
    until = f' (until {html.escape(str(acct.get("expires", "")))})' if acct.get("expires") else ""
    if days <= 0:
        msg, cls = f"Your {name} premium has expired: nothing will play until you renew.", "expired"
    elif days == 1:
        msg, cls = f"Your {name} premium expires tomorrow{until}.", "expired"
    else:
        msg, cls = f"Your {name} premium expires in {days} days{until}.", "expired" if days <= 2 else "soon"
    return (f'<div class="card banner {cls}"><b>{msg}</b> '
            f'<a href="{url}" target="_blank" rel="noopener noreferrer">Renew at {html.escape(name)} ↗</a></div>')


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
<p style="margin:0 0 10px"><a href="/power">Power switch</a>: one green and one red button, made for your phone.</p>
{button(session, "restart", "Restart stack")}
{button(session, "maintenance_off" if maint else "maintenance_on", "Resume watchdog" if maint else "Pause watchdog (maintenance)", secondary=True)}
{button(session, "plex_setup", "Re-apply Plex settings", secondary=True)}
<p>{ext_link(*PROVIDER_LINKS.get(s.get("provider", "realdebrid"), PROVIDER_LINKS["realdebrid"]))} · add movies and shows to your library</p>
<p class="muted">Actions are applied by the host within a minute. Pending: {pending()}.</p></div>
<div class="card"><h2>Recent actions</h2>{results_table()}</div>"""


SECRET = DATA / "secret"
PROVIDER_LINKS = {
    "realdebrid": ("Debrid Media Manager", "https://debridmediamanager.com"),
    "torbox": ("TorBox dashboard", "https://torbox.app/dashboard"),
}


def read_secret(name):
    try:
        v = (SECRET / name).read_text().strip()
        return v if KEY_RE.match(v) else ""
    except OSError:
        return ""


def ext_link(label, url, cls=""):
    c = f' class="{cls}"' if cls else ""
    return f'<a{c} href="{url}" target="_blank" rel="noopener noreferrer">{html.escape(label)} ↗</a>'


def key_block(session, which, revealed=""):
    """Current key: masked, or in full after the password was re-entered."""
    key = read_secret(f"{which}.key")
    if not key:
        return '<p class="muted">No key saved.</p>'
    if revealed == which:
        return (f'<label for="cur-{which}">Current key</label>'
                f'<input id="cur-{which}" value="{html.escape(key)}" readonly spellcheck="false" autocomplete="off">'
                '<p class="muted">Shown because you re-entered your password. It is hidden again when you leave this page.</p>')
    return (f'<p>Current key: <code>••••••••••••{html.escape(key[-4:])}</code></p>'
            f'<form method="post" action="/reveal" class="row">{csrf_field(session)}<input type="hidden" name="which" value="{which}">'
            f'<div><label for="pw-{which}">Password to show the full key</label>'
            f'<input id="pw-{which}" name="password" type="password" autocomplete="current-password" required></div>'
            '<button class="secondary">Show</button></form>')


def keys_body(session, revealed="", error=""):
    s = read_json("status.json")
    cur = s.get("provider", "realdebrid")
    other = "torbox" if cur == "realdebrid" else "realdebrid"
    names = {"realdebrid": "Real-Debrid", "torbox": "TorBox (experimental)"}
    other_set = s.get("torbox_key_set") if other == "torbox" else s.get("rd_key_set")
    switch = (button(session, "switch_provider", f"Switch to {names[other]}", other, secondary=True)
              if other_set else f'<p class="muted">Save a {names[other]} key first to enable switching.</p>')
    err = f'<div class="card"><p class="bad">{html.escape(error)}</p></div>' if error else ""
    return f"""{err}
<div class="card"><h2>Real-Debrid</h2>
{key_block(session, "rd", revealed)}
<form method="post" action="/action" class="row">{csrf_field(session)}<input type="hidden" name="action" value="set_rd_token">
<div><label for="rd">New key</label><input id="rd" name="value" type="password" autocomplete="off" required></div><button>Save</button></form>
<p class="muted">Get a key at {ext_link("real-debrid.com/apitoken", "https://real-debrid.com/apitoken")}; it's checked with Real-Debrid before it's saved.
Add content with {ext_link(*PROVIDER_LINKS["realdebrid"])}.</p></div>
<div class="card"><h2>TorBox</h2>
{key_block(session, "torbox", revealed)}
<form method="post" action="/action" class="row">{csrf_field(session)}<input type="hidden" name="action" value="set_torbox_key">
<div><label for="tb">New key</label><input id="tb" name="value" type="password" autocomplete="off" required></div><button>Save</button></form>
<p class="muted">Get a key at {ext_link("torbox.app/settings", "https://torbox.app/settings")}.</p></div>
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


def password_body(session, error=""):
    err = f'<p class="bad">{html.escape(error)}</p>' if error else ""
    return f"""<div class="card" style="max-width:460px"><h2>Change password</h2>{err}
<form method="post" action="/password">{csrf_field(session)}
<label for="cur">Current password</label><input id="cur" name="current" type="password" autocomplete="current-password" required>
<label for="new">New password (at least 8 characters)</label><input id="new" name="new" type="password" autocomplete="new-password" minlength="8" required>
<label for="rep">Repeat new password</label><input id="rep" name="repeat" type="password" autocomplete="new-password" minlength="8" required>
<p><button>Change password</button></p></form>
<p class="muted">Other open sessions are logged out. Forgot it? Reset over SSH: <code>sudo bash scripts/admin-setup.sh</code></p></div>"""


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
        self.send_header("Content-Security-Policy", (headers or {}).get("Content-Security-Policy",
                         "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'"))
        for k, v in (headers or {}).items():
            if k != "Content-Security-Policy":
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
            if s and time.time() - s["seen"] < s.get("idle", SESSION_IDLE):
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
        if path in ("/demo", "/demo/", "/demo.js"):
            return self.demo(path)
        if path == "/ca.crt":     # the local CA's public certificate: no secret, needed before login
            try:
                return self.send(200, (AUTH / "ca.pem").read_bytes(), "application/x-x509-ca-cert",
                                 {"Content-Disposition": 'attachment; filename="debrid-admin-ca.crt"'})
            except OSError:
                return self.send(404, "no certificate authority (run scripts/admin-cert.sh)", "text/plain")
        if path == "/certificate":
            return self.send(200, page("Certificate", certificate_body(self.headers.get("Host", ""))))
        token, s = self.session()
        if not s:
            if path == "/login":
                nxt = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("next", [""])[0]
                return self.send(200, login_page(nxt=nxt if nxt in SAFE_NEXT else ""))
            return self.redirect(("/login?next=" + urllib.parse.quote(path)) if path in SAFE_NEXT else "/login")
        flash = urllib.parse.parse_qs(urllib.parse.urlsplit(self.path).query).get("m", [""])[0][:200]
        if path == "/power":
            return self.send(200, power_page(s), headers={"Content-Security-Policy": POWER_CSP})
        if path == "/power.js":
            return self.send(200, POWER_JS, "text/javascript; charset=utf-8")
        if path == "/power/status":
            return self.send(200, json.dumps(power_status()), "application/json")
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
        if path == "/password":
            return self.send(200, page("Password", password_body(s), s, flash))
        if path == "/log":
            return self.send(200, page("Log", log_body(s), s))
        return self.send(404, page("Not found", "<p>Not found.</p>", s))

    do_HEAD = do_GET

    def demo(self, path):
        name, ctype = ("demo.js", "text/javascript; charset=utf-8") if path == "/demo.js" else ("index.html", "text/html; charset=utf-8")
        try:
            data = (DEMO_DIR / name).read_bytes()
        except OSError:
            return self.send(404, "demo not installed", "text/plain")
        # The demo page may run its own script from this server, nothing else
        csp = "default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        return self.send(200, data, ctype, {"Content-Security-Policy": csp})

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
        if path == "/password":
            return self.change_password(token, s, f)
        if path == "/reveal":
            return self.reveal(s, f)
        return self.send(404, page("Not found", "<p>Not found.</p>", s))

    def login(self, f):
        if locked_out():
            return self.send(429, login_page("Too many failed attempts. Try again in 15 minutes."))
        if check_password(f.get("password", "")):
            token = secrets.token_urlsafe(32)
            idle = REMEMBER_IDLE if f.get("remember") == "yes" else SESSION_IDLE
            with lock:
                fails.clear()
                sessions[token] = {"csrf": secrets.token_urlsafe(32), "seen": time.time(), "idle": idle}
            nxt = f.get("next", "")
            return self.redirect(nxt if nxt in SAFE_NEXT else "/", {"Set-Cookie": self.cookie(token, idle)})
        record_fail()
        return self.send(401, login_page("Wrong password."))

    def reveal(self, s, f):
        which = f.get("which", "")
        if which not in ("rd", "torbox"):
            return self.redirect("/keys")
        if locked_out():
            return self.send(429, page("Keys", keys_body(s, error="Too many failed attempts. Try again in 15 minutes."), s))
        if not check_password(f.get("password", "")):
            record_fail()
            return self.send(401, page("Keys", keys_body(s, error="Wrong password."), s))
        return self.send(200, page("Keys", keys_body(s, revealed=which), s))

    def change_password(self, token, s, f):
        def again(msg, code=400):
            return self.send(code, page("Password", password_body(s, msg), s))
        if locked_out():
            return again("Too many failed attempts. Try again in 15 minutes.", 429)
        new, repeat = f.get("new", ""), f.get("repeat", "")
        if not check_password(f.get("current", "")):
            record_fail()       # counts towards the lockout, like a failed login
            return again("Current password is wrong.", 401)
        if len(new) < 8 or len(new) > 200:
            return again("The new password must be 8 to 200 characters.")
        if new != repeat:
            return again("The new passwords don't match.")
        if new == f.get("current"):
            return again("The new password is the same as the current one.")
        try:
            save_password(new)
        except OSError:
            return again("Could not save the password (is admin/auth writable for the page?).", 500)
        # Log out every other session; keep this one, with a fresh token
        new_token = secrets.token_urlsafe(32)
        with lock:
            sessions.clear()
            fails.clear()
            sessions[new_token] = {"csrf": secrets.token_urlsafe(32), "seen": time.time()}
        return self.redirect("/password?m=" + urllib.parse.quote("Password changed. Other sessions were logged out."),
                             {"Set-Cookie": self.cookie(new_token, SESSION_IDLE)})

    def action(self, f):
        action, value = f.get("action", ""), f.get("value", "").strip()
        if action in ("power_on", "power_off"):
            if not any(a in ("power_on", "power_off") for a in pending_actions()):
                queue(action, "")
            if self.headers.get("X-Requested-With") == "fetch":
                return self.send(200, json.dumps(power_status()), "application/json")
            return self.redirect("/power")
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


# Live map of the stack, linked from the login page (override with ADMIN_DEMO_URL)
DEMO_URL = os.environ.get("ADMIN_DEMO_URL", "/demo")
DEMO_DIR = Path(os.environ.get("ADMIN_DEMO_DIR", "/app/demo"))


# ------------------------------------------------------------------ power switch
# A phone-sized page with one green and one red button. The buttons queue power_on /
# power_off; scripts/agent.sh applies them and publishes power.json while it works.

POWER_CSP = ("default-src 'none'; script-src 'self'; style-src 'unsafe-inline'; connect-src 'self'; "
             "form-action 'self'; frame-ancestors 'none'; base-uri 'none'")

POWER_TEXT = {
    "on": ("Plex is running", "Ready to watch"),
    "off": ("Plex is off", "Tap the green button to start it"),
    "starting": ("Starting Plex…", "waiting for the host"),
    "stopping": ("Stopping Plex…", "closing Plex and the library"),
    "degraded": ("Not fully running", "The watchdog is trying to repair it"),
    "unknown": ("Checking…", ""),
}


def pending_actions():
    """Names of the requests waiting in the inbox (oldest first)."""
    acts = []
    for f in sorted(REQUESTS.glob("*.req")):
        try:
            for line in f.read_text().splitlines():
                if line.startswith("action="):
                    acts.append(line[7:].strip())
                    break
        except OSError:
            pass
    return acts


def power_status():
    p, st = read_json("power.json"), read_json("status.json")
    busy = read_text("busy.txt").split("\t")[0].strip()
    try:  # a leftover busy marker from a crashed run must not show "starting" forever
        if time.time() - (STATE / "busy.txt").stat().st_mtime > 900:
            busy = ""
    except OSError:
        busy = ""

    def num(k):
        v = p.get(k)
        return v if isinstance(v, int) and v >= 0 else 0
    return {"phase": p.get("phase") if p.get("phase") in POWER_TEXT else "unknown",
            "stage": str(p.get("stage", ""))[:120],
            "since": num("since"), "estimate": num("estimate"), "last_start_secs": num("last_start_secs"),
            "updated": num("updated"),
            "busy": busy if busy in ("power_on", "power_off") else "",
            "pending": [a for a in pending_actions() if a in ("power_on", "power_off")],
            "containers": st.get("containers", {}) if isinstance(st.get("containers"), dict) else {},
            "now": int(time.time())}


POWER_CSS = """
:root{color-scheme:light dark;--bg:#f4f5f9;--card:#fff;--fg:#111827;--muted:#6b7280;--line:#e5e7ef;--on:#16a34a;--on-2:#22c55e;--off:#dc2626;--off-2:#ef4444;--amber:#d97706}
@media(prefers-color-scheme:dark){:root{--bg:#0b0d12;--card:#12151d;--fg:#e8eaf0;--muted:#8d95a8;--line:#242a38;--on:#22c55e;--on-2:#4ade80;--off:#ef4444;--off-2:#f87171;--amber:#fbbf24}}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%}
body{background:var(--bg);color:var(--fg);font:16px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;-webkit-font-smoothing:antialiased;-webkit-tap-highlight-color:transparent}
.pw{max-width:420px;margin:0 auto;min-height:100vh;min-height:100dvh;display:flex;flex-direction:column;padding:max(16px,env(safe-area-inset-top)) 20px max(28px,env(safe-area-inset-bottom))}
header{display:flex;align-items:center;justify-content:space-between;gap:12px}
header a{color:var(--muted);text-decoration:none;font-size:14px;padding:6px 0}
h1{font-size:20px;margin:0;letter-spacing:-.01em}
.state{display:flex;align-items:center;gap:14px;margin:26px 0 0;padding:16px 18px;background:var(--card);border:1px solid var(--line);border-radius:18px}
.dot{width:14px;height:14px;border-radius:50%;background:var(--muted);flex:none;box-shadow:0 0 0 4px color-mix(in srgb,var(--muted) 18%,transparent)}
[data-phase=on] .dot{background:var(--on);box-shadow:0 0 0 4px color-mix(in srgb,var(--on) 22%,transparent)}
[data-phase=off] .dot{background:var(--off);box-shadow:0 0 0 4px color-mix(in srgb,var(--off) 22%,transparent)}
[data-phase=starting] .dot,[data-phase=stopping] .dot,[data-phase=degraded] .dot{background:var(--amber);box-shadow:0 0 0 4px color-mix(in srgb,var(--amber) 22%,transparent)}
[data-phase=starting] .dot,[data-phase=stopping] .dot{animation:pulse 1.2s ease-in-out infinite}
@keyframes pulse{50%{opacity:.35}}
.state b{display:block;font-size:17px}
.state span{display:block;color:var(--muted);font-size:14px;min-height:21px}
.ring{position:relative;width:200px;height:200px;margin:30px auto 0}
.ring svg{width:100%;height:100%;transform:rotate(-90deg)}
.ring circle{fill:none;stroke-width:9;stroke-linecap:round}
.ring .track{stroke:var(--line)}
.ring .bar{stroke:var(--on);transition:stroke-dashoffset .5s linear}
[data-phase=stopping] .ring .bar{stroke:var(--off)}
.ring .num{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.ring .num b{font-size:54px;line-height:1;font-variant-numeric:tabular-nums;letter-spacing:-.02em}
.ring .num small{color:var(--muted);font-size:13px;margin-top:6px}
.ring[hidden]{display:none}
.btns{display:flex;justify-content:center;gap:36px;margin:auto 0 0;padding-top:30px}
.btns form{display:flex;flex-direction:column;align-items:center;gap:10px;margin:0;font-size:14px;color:var(--muted);font-weight:600}
.big{width:118px;height:118px;border-radius:50%;border:0;color:#fff;cursor:pointer;display:grid;place-items:center;transition:transform .12s ease,filter .2s,opacity .2s;-webkit-appearance:none;appearance:none;touch-action:manipulation;padding:0}
.big:active{transform:scale(.94)}
.big:disabled{filter:grayscale(.8);opacity:.35;cursor:default;box-shadow:none}
.big svg{width:46px;height:46px;fill:currentColor}
.on{background:linear-gradient(145deg,var(--on-2),var(--on));box-shadow:0 14px 30px -12px var(--on)}
.off{background:linear-gradient(145deg,var(--off-2),var(--off));box-shadow:0 14px 30px -12px var(--off)}
.hint{text-align:center;color:var(--muted);font-size:13px;margin:22px 0 0;min-height:20px}
noscript p{text-align:center;color:var(--muted);font-size:13px}
@media(prefers-reduced-motion:reduce){.dot{animation:none!important}.ring .bar{transition:none}}
"""

POWER_JS = r"""(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var pw = $("pw"), label = $("label"), stage = $("stage"), ring = $("ring"), bar = $("bar");
  var count = $("count"), unit = $("unit"), hint = $("hint"), bOn = $("b-on"), bOff = $("b-off");
  var TEXT = JSON.parse(pw.dataset.text);
  var C = 2 * Math.PI * 54;
  bar.style.strokeDasharray = C; bar.style.strokeDashoffset = C;
  var tap = null;        // {phase, t0}: what the last tap asked for, until the host confirms it
  var stale = false;     // the host never picked the tap up
  var offset = 0;        // server clock minus phone clock (seconds)
  var state = null, tickTimer = null, pollTimer = null;

  function now() { return Date.now() / 1000 + offset; }

  // Effective phase: the inbox and the busy marker are the host's truth; a tap counts
  // for 15 s (until the host has picked it up), unless the host is already done
  function phaseOf(s) {
    var q = s.pending || [], ph = s.phase || "unknown";
    if (s.busy === "power_on" || q.indexOf("power_on") >= 0) ph = "starting";
    else if (s.busy === "power_off" || q.indexOf("power_off") >= 0) ph = "stopping";
    if (tap) {
      var done = (tap.phase === "starting" && ph === "on") || (tap.phase === "stopping" && ph === "off");
      if (ph === tap.phase) return ph;
      if (done) { tap = null; return ph; }
      if (now() - tap.t0 < 15 && ph !== "starting" && ph !== "stopping") return tap.phase;
      stale = ph !== "starting" && ph !== "stopping";
      tap = null;
    }
    return ph;
  }

  function render(s) {
    state = s;
    if (s.now) offset = s.now - Date.now() / 1000;
    var ph = phaseOf(s), busy = ph === "starting" || ph === "stopping";
    pw.dataset.phase = ph;
    label.textContent = (TEXT[ph] || TEXT.unknown)[0];
    stage.textContent = busy && s.phase === ph && s.stage ? s.stage : (TEXT[ph] || TEXT.unknown)[1];
    bOn.disabled = ph === "on" || busy;
    bOff.disabled = ph === "off" || busy;
    if (busy) {
      ring.hidden = false; tick();
      if (!tickTimer) tickTimer = setInterval(tick, 250);
    } else {
      ring.hidden = true;
      if (tickTimer) { clearInterval(tickTimer); tickTimer = null; }
      bar.style.strokeDashoffset = C;
    }
    if (stale) hint.textContent = "The host has not picked this up. Is the watchdog task running?";
    else if (ph === "on" && s.last_start_secs) hint.textContent = "Last start took " + s.last_start_secs + " seconds.";
    else if (ph === "degraded") hint.textContent = "If this stays for a few minutes, tap Start again or check the log.";
    else hint.textContent = "";
    schedule(busy ? 2000 : 10000);
  }

  // Countdown: from the host's own start time once it has one, else from the tap
  function tick() {
    var s = state, ph = pw.dataset.phase;
    var fromHost = s.phase === ph && s.since > 0;
    var t0 = fromHost ? s.since : (tap ? tap.t0 : now());
    if (fromHost && tap && tap.t0 < t0) t0 = tap.t0;
    var est = fromHost && s.estimate ? s.estimate : (ph === "stopping" ? 15 : (s.last_start_secs ? s.last_start_secs + 30 : 120));
    var left = Math.ceil(est - (now() - t0));
    count.textContent = left > 0 ? left : "…";
    unit.textContent = left > 0 ? "seconds" : (ph === "starting" ? "almost there" : "finishing");
    bar.style.strokeDashoffset = C * (1 - Math.min(1, (now() - t0) / est));
  }

  function schedule(ms) { if (pollTimer) clearTimeout(pollTimer); pollTimer = setTimeout(poll, ms); }
  function poll() {
    fetch("/power/status", { credentials: "same-origin", headers: { "Accept": "application/json" } })
      .then(function (r) {
        if (r.redirected || (r.headers.get("content-type") || "").indexOf("json") < 0) { location.reload(); throw 0; }
        return r.json();
      })
      .then(render)
      .catch(function () { stage.textContent = "connection lost, retrying…"; schedule(4000); });
  }

  function arm(form, phase, ask) {
    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      if (ask && !window.confirm(ask)) return;
      tap = { phase: phase, t0: now() }; stale = false;
      form.querySelector("button").disabled = true;
      fetch("/action", { method: "POST", body: new URLSearchParams(new FormData(form)), credentials: "same-origin",
                         headers: { "X-Requested-With": "fetch", "Accept": "application/json" } })
        .then(function (r) { if (!r.ok || r.redirected) throw 0; return r.json(); })
        .then(render)
        .catch(function () { location.reload(); });
    });
  }
  arm($("f-on"), "starting", null);
  arm($("f-off"), "stopping", "Stop Plex? Anyone watching right now is cut off.");
  document.addEventListener("visibilitychange", function () { if (!document.hidden) poll(); });
  render(JSON.parse(pw.dataset.state));
})();
"""


def power_page(session):
    e = html.escape
    s = power_status()
    ph = s["phase"]
    if s["busy"] == "power_on" or "power_on" in s["pending"]:
        ph = "starting"
    elif s["busy"] == "power_off" or "power_off" in s["pending"]:
        ph = "stopping"
    title, sub = POWER_TEXT[ph]
    play = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5v14l11-7z"/></svg>'
    stop = '<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/></svg>'
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"><meta name="color-scheme" content="light dark">
<meta name="apple-mobile-web-app-title" content="Plex"><meta name="format-detection" content="telephone=no">
<title>Plex power · debrid</title><style>{POWER_CSS}</style></head>
<body><main class="pw" id="pw" data-phase="{e(ph)}" data-state='{e(json.dumps(s))}' data-text='{e(json.dumps(POWER_TEXT))}'>
<header><a href="/">‹ Management page</a><h1>Plex power</h1><a href="/power" aria-label="Refresh">↻</a></header>
<div class="state"><div class="dot"></div><div><b id="label">{e(title)}</b><span id="stage">{e(sub)}</span></div></div>
<div class="ring" id="ring" hidden><svg viewBox="0 0 120 120"><circle class="track" cx="60" cy="60" r="54"/><circle class="bar" id="bar" cx="60" cy="60" r="54"/></svg>
<div class="num"><b id="count">–</b><small id="unit">seconds</small></div></div>
<div class="btns">
<form method="post" action="/action" id="f-on">{csrf_field(session)}<input type="hidden" name="action" value="power_on"><button class="big on" id="b-on" aria-label="Start Plex"{" disabled" if ph in ("on", "starting", "stopping") else ""}>{play}</button>Start</form>
<form method="post" action="/action" id="f-off">{csrf_field(session)}<input type="hidden" name="action" value="power_off"><button class="big off" id="b-off" aria-label="Stop Plex"{" disabled" if ph in ("off", "starting", "stopping") else ""}>{stop}</button>Stop</form>
</div>
<p class="hint" id="hint"></p>
<noscript><p>Without JavaScript the buttons still work; reload the page to see the result.</p></noscript>
</main><script src="/power.js" defer></script></body></html>"""


def certificate_body(host):
    """How to install the page's CA so browsers stop warning (public page)."""
    host = host if re.match(r"^[A-Za-z0-9.\-]+(:\d{1,5})?$", host or "") else ""
    dl = html.escape(f"http://{host}/ca.crt" if host else "/ca.crt")
    return f"""<div class="card">
<h2>Remove the certificate warning</h2>
<p class="muted">This page uses its own certificate, so browsers warn that the connection is "not private".
Install the page's certificate authority once on each device and the warning is gone. The file contains no secrets.</p>
<p><a href="{dl}"><b>Download the certificate</b></a> <span class="muted">(plain http, so it works before the warning is gone)</span></p>
<h3>iPhone / iPad</h3>
<ol>
<li>Open the download link above in Safari and tap <b>Allow</b> (Tillat) when it asks to download a profile.</li>
<li>Settings → General → VPN &amp; Device Management (Innstillinger → Generelt → VPN og enhetsadministrasjon) → <b>debrid-admin local CA</b> → Install.</li>
<li>Settings → General → About → Certificate Trust Settings (Om → Innstillinger for sertifikatklarering) → switch on <b>debrid-admin local CA</b>.</li>
<li>Close the tab and open the page again.</li>
</ol>
<h3>Android</h3>
<ol>
<li>Download the certificate with the link above (Chrome).</li>
<li>Settings → Security → Encryption &amp; credentials → Install a certificate → <b>CA certificate</b> → Install anyway → pick the downloaded file.</li>
</ol>
<h3>Windows</h3>
<ol><li>Download, double-click the file → Install Certificate → Current User → <b>Place all certificates in the following store</b> → Trusted Root Certification Authorities.</li></ol>
<h3>Mac</h3>
<ol><li>Download, double-click to add it to Keychain Access, open it there and set Trust → <b>Always Trust</b>.</li></ol>
<p class="muted">The server certificate is renewed automatically; the installed authority stays valid for 10 years.</p>
<p><a href="/login">Back to log in</a></p></div>"""


def login_page(msg="", nxt=""):
    m = f'<p class="bad">{html.escape(msg)}</p>' if msg else ""
    return page("Log in", f"""<div class="card" style="max-width:380px;margin:40px auto">
<h2>Log in</h2>{m}<form method="post" action="/login">
<label for="user">Username</label><input id="user" name="username" value="admin" autocomplete="username" readonly>
<label for="pw">Password</label><input id="pw" name="password" type="password" autocomplete="current-password" autofocus required>
<label style="display:flex;gap:8px;align-items:center;font-weight:400;margin:10px 0 14px"><input type="checkbox" name="remember" value="yes" style="width:auto;margin:0"> Keep me signed in on this device (30 days)</label><input type="hidden" name="next" value="{html.escape(nxt)}">
<p><button>Log in</button></p></form><p class="muted">Only reachable from your home network. <a href="/certificate">Remove the certificate warning</a></p>
<p><a href="{html.escape(DEMO_URL)}" target="_blank" rel="noopener noreferrer">How it works: live map ↗</a></p></div>""")


class Server(ThreadingHTTPServer):
    daemon_threads = True
    ssl_ctx = None

    @property
    def tls(self):
        return self.ssl_ctx is not None

    def finish_request(self, request, client_address):
        # TLS handshake per connection in the worker thread, so a slow client can't
        # block the accept loop
        request.settimeout(30)
        if self.ssl_ctx:
            try:
                first = request.recv(1, socket.MSG_PEEK)
            except OSError:
                return
            if first and first != b"\x16":      # not a TLS handshake: plain http:// typed
                return redirect_to_https(request)
            try:
                request = self.ssl_ctx.wrap_socket(request, server_side=True)
            except (ssl.SSLError, OSError):
                return
        super().finish_request(request, client_address)


def redirect_to_https(sock):
    """Answer a plain-HTTP request on the HTTPS port with a redirect instead of an empty reply."""
    try:
        head = sock.recv(4096).decode("latin-1", "replace")
        if re.match(r"^GET /ca\.crt(\?\S*)? HTTP/", head) and (AUTH / "ca.pem").is_file():
            body = (AUTH / "ca.pem").read_bytes()   # public: lets a phone fetch the CA before it trusts us
            sock.sendall(b"HTTP/1.1 200 OK\r\nContent-Type: application/x-x509-ca-cert\r\n"
                         b'Content-Disposition: attachment; filename="debrid-admin-ca.crt"\r\n'
                         b"Content-Length: %d\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n" % len(body) + body)
            return
        m = re.search(r"^Host:\s*([A-Za-z0-9.\-]+(?::\d{1,5})?)\s*$", head, re.I | re.M)
        target = f"https://{m.group(1)}/" if m else None
        if target:
            body = f'<a href="{target}">{target}</a>'
            sock.sendall((f"HTTP/1.1 301 Moved Permanently\r\nLocation: {target}\r\nContent-Type: text/html\r\n"
                          f"Content-Length: {len(body)}\r\nConnection: close\r\n\r\n{body}").encode())
        else:
            msg = b"Use https:// to open this page.\r\n"
            sock.sendall(b"HTTP/1.1 400 Bad Request\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % (len(msg), msg))
    except OSError:
        pass
    finally:
        try:
            sock.close()
        except OSError:
            pass


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
