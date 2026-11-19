"""Adds FOLK Event.is_weekly (a weekly programme such as the Saturday Satsang) and turns it on for the event FOLK.
A weekly event shows its call numbers for the current Monday-Sunday week only; nothing is deleted. Re-runnable.

  python3 -I scripts/phase19_weekly_event.py             dry run: writes NOTHING
  python3 -I scripts/phase19_weekly_event.py --commit    really writes"""
import json, os, sys, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json",
     "User-Agent": "folk-setup/1.0", "Accept": "application/json"}


def call(method, path, body=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:800]}


s, d = call("GET", "/api/resource/DocType/FOLK%20Event")
if s != 200: raise SystemExit(f"! cannot read the FOLK Event doctype: {s} {d}")
doc = d["data"]; fields = doc["fields"]
if any(f["fieldname"] == "is_weekly" for f in fields):
    print("= is_weekly already exists")
else:
    print("+ add FOLK Event.is_weekly (checkbox)")
    if COMMIT:
        fields.append({"fieldname": "is_weekly", "label": "Weekly event (call numbers count Monday-Sunday)", "fieldtype": "Check", "default": "0"})
        s, r = call("PUT", "/api/resource/DocType/FOLK%20Event", doc)
        print("  saved" if s == 200 else f"  ! {s} {r}")
s, r = call("GET", "/api/resource/FOLK%20Event/FOLK")
print(f"{'+' if COMMIT else '~'} turn on is_weekly for FOLK ({(r.get('data') or {}).get('event_name')})")
if COMMIT:
    s, r = call("PUT", "/api/resource/FOLK%20Event/FOLK", {"is_weekly": 1})
    print("  saved" if s == 200 else f"  ! {s} {r}")
print("COMMITTED" if COMMIT else "DRY RUN (nothing written)")
