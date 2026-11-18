"""Adds FOLK Attendance.marked_by_name (auto-filled from the volunteer's name). Re-runnable."""
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
        return e.code, {"error": e.read().decode()[:500]}


s, d = call("GET", "/api/resource/DocType/FOLK%20Attendance")
fields = d["data"]["fields"]
if not any(f["fieldname"] == "marked_by_name" for f in fields):
    i = next(i for i, f in enumerate(fields) if f["fieldname"] == "marked_by")
    fields.insert(i + 1, {"fieldname": "marked_by_name", "label": "Marked By Name", "fieldtype": "Data", "fetch_from": "marked_by.full_name", "read_only": 1})
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Attendance", d["data"])
    print("+ marked_by_name added" if s == 200 else f"! {s} {r}")
else:
    print("= marked_by_name already exists")

# Backfill existing rows
s, rows = call("GET", "/api/resource/FOLK%20Attendance?fields=%5B%22name%22%2C%22marked_by%22%5D&limit_page_length=0")
s, ppl = call("GET", "/api/resource/FOLK%20Users?fields=%5B%22name%22%2C%22full_name%22%5D&limit_page_length=0")
nm = {p["name"]: p["full_name"] for p in ppl["data"]}
for r in rows["data"]:
    if r.get("marked_by") in nm:
        s, _ = call("PUT", "/api/resource/FOLK%20Attendance/" + urllib.request.quote(r["name"]), {"marked_by_name": nm[r["marked_by"]]})
        print("backfilled", r["name"], s)
