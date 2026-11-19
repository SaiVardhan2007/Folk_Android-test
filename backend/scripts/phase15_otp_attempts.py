"""Adds FOLK Users.reset_attempts (wrong SMS-code tries, max 5 per code). Re-runnable."""
import json, os, urllib.request, urllib.error

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


s, d = call("GET", "/api/resource/DocType/FOLK%20Users")
doc = d["data"]; fields = doc["fields"]
if any(f["fieldname"] == "reset_attempts" for f in fields):
    print("= reset_attempts already exists")
else:
    fields.append({"fieldname": "reset_attempts", "label": "Wrong reset-code tries", "fieldtype": "Int", "default": "0", "hidden": 1})
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", doc)
    print("+ reset_attempts", "saved" if s == 200 else f"! {s} {r}")
