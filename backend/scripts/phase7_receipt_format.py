"""Adds FOLK Settings.receipt_format (JSON of the printed attendance receipt layout). Re-runnable."""
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


s, d = call("GET", "/api/resource/DocType/FOLK%20Settings")
doc = d["data"]; fields = doc["fields"]
if any(f["fieldname"] == "receipt_format" for f in fields):
    print("= receipt_format already exists")
else:
    fields.append({"fieldname": "receipt_format", "label": "Receipt format (JSON)", "fieldtype": "Long Text"})
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Settings", doc)
    print("+ receipt_format", "saved" if s == 200 else f"! {s} {r}")
