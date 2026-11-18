"""One-time: give existing FOLK Users generated IDs (FP-#####) and repoint attendance. Safe to re-run (skips already migrated)."""
import json, os, re, urllib.request, urllib.error, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json",
     "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote


def call(method, path, body=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:800]}


s, r = call("GET", "/api/resource/FOLK%20Users?fields=%5B%22name%22%2C%22mob_no%22%2C%22user_tag%22%5D&limit_page_length=0&order_by=creation%20asc")
people = r["data"]
old = [p for p in people if not re.fullmatch(r"FP-\d{5}", p["name"])]
print("to migrate:", [p["name"] for p in old])
if not old:
    raise SystemExit("nothing to do")

# 1. Reserve fresh IDs from the series (create + delete placeholders), so the counter moves past them.
ids = []
for i in range(len(old)):
    s, r = call("POST", "/api/resource/FOLK%20Users", {"mob_no": f"000000000{i}", "full_name": "tmp"})
    assert s == 200, r
    ids.append(r["data"]["name"])
for n in ids:
    call("DELETE", "/api/resource/FOLK%20Users/" + q(n))
print("reserved IDs:", ids)

# 2. Roles: People -> Public
for p in old:
    if p["user_tag"] == "People":
        call("PUT", "/api/resource/FOLK%20Users/" + q(p["name"]), {"user_tag": "Public"})

# 3. Rename each person (Frappe rewrites Link fields such as attendance.person / marked_by).
mapping = {}
for p, new in zip(old, ids):
    s, r = call("POST", "/api/method/frappe.client.rename_doc", {"doctype": "FOLK Users", "old_name": p["name"], "new_name": new})
    print(p["name"], "->", new, s, "" if s == 200 else r)
    if s == 200:
        mapping[p["name"]] = new

# 4. Rename attendance rows so their IDs follow the {event}-{date}-{person} rule.
s, r = call("GET", "/api/resource/FOLK%20Attendance?fields=%5B%22name%22%2C%22event_code%22%2C%22attendance_date%22%2C%22person%22%5D&limit_page_length=0")
for a in r["data"]:
    want = f"{a['event_code']}-{a['attendance_date']}-{a['person']}"
    if a["name"] != want:
        s, rr = call("POST", "/api/method/frappe.client.rename_doc", {"doctype": "FOLK Attendance", "old_name": a["name"], "new_name": want})
        print("attendance", a["name"], "->", want, s, "" if s == 200 else rr)
print("mapping:", mapping)
