"""Phase 1b: reuse FOLK Users (no FOLK Person), repoint FOLK Attendance links, copy old attendance rows.
Does NOT delete the old child table. Re-runnable. Run: python3 -I scripts/phase1b_reuse_folk_users.py
"""
import json, os, urllib.request, urllib.error, urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
env = {}
for line in open(os.path.join(HERE, "..", ".dev.vars")):
    if "=" in line:
        k, v = line.strip().split("=", 1)
        env[k] = v
BASE = env["ERPNEXT_URL"]
AUTH = f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}"


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path, method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": AUTH, "Content-Type": "application/json",
                 "User-Agent": "folk-setup/1.0", "Accept": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:800]}


q = urllib.parse.quote

# 1. Repoint FOLK Attendance links: FOLK Person -> FOLK Users
s, d = call("GET", "/api/resource/DocType/FOLK%20Attendance")
assert s == 200, d
changed = False
for f in d["data"]["fields"]:
    if f.get("options") == "FOLK Person":
        f["options"] = "FOLK Users"; changed = True
    if f["fieldname"] == "person_name" and f.get("fetch_from") != "person.full_name":
        f["fetch_from"] = "person.full_name"; changed = True
if changed:
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Attendance", d["data"])
    print("+ FOLK Attendance links -> FOLK Users" if s == 200 else f"! {s} {r}")
else:
    print("= FOLK Attendance links already point to FOLK Users")

# 2. Delete the (empty) FOLK Person
s, p = call("GET", "/api/method/frappe.client.get_count?doctype=FOLK%20Person")
if s == 200:
    cnt = p.get("message")
    if cnt == 0:
        s, r = call("DELETE", "/api/resource/DocType/FOLK%20Person")
        print("- deleted empty FOLK Person" if s in (200, 202) else f"! delete FOLK Person failed {s} {r}")
    else:
        print(f"! FOLK Person has {cnt} records, NOT deleting")
else:
    print("= FOLK Person already gone")

# 3. Add missing fields to FOLK Users
s, u = call("GET", "/api/resource/DocType/FOLK%20Users")
assert s == 200, u
have = {f["fieldname"] for f in u["data"]["fields"]}
new = [
    {"fieldname": "occupation", "label": "Occupation", "fieldtype": "Select", "options": "\nStudent\nJob Search\nWorking", "insert_after": "profession"},
    {"fieldname": "is_active", "label": "Active", "fieldtype": "Check", "default": "1", "insert_after": "user_tag"},
    {"fieldname": "reset_code_hash", "label": "Reset Code Hash", "fieldtype": "Data", "read_only": 1, "insert_after": "password_hash"},
    {"fieldname": "reset_code_expires", "label": "Reset Code Expires", "fieldtype": "Datetime", "read_only": 1, "insert_after": "reset_code_hash"},
]
add = [f for f in new if f["fieldname"] not in have]
if add:
    fields = u["data"]["fields"]
    for nf in add:
        idx = next((i for i, f in enumerate(fields) if f["fieldname"] == nf["insert_after"]), len(fields) - 1)
        nf.pop("insert_after")
        fields.insert(idx + 1, nf)
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", u["data"])
    print(f"+ FOLK Users: added {[f['fieldname'] for f in add]}" if s == 200 else f"! {s} {r}")
else:
    print("= FOLK Users already has the new fields")

# 4. Mark the existing FOLK event as current
s, r = call("PUT", "/api/resource/FOLK%20Event/FOLK", {"is_current": 1})
print("+ FOLK event is_current = 1" if s == 200 else f"! {s} {r}")

# 5. Copy old attendance rows -> FOLK Attendance (skips ones that exist)
fields = json.dumps(["parent", "event_code", "attendance_date", "ts", "marked_by"])
s, r = call("GET", "/api/method/frappe.client.get_list?doctype=FOLK%20Users%20Attendance&parent=FOLK%20Users"
            f"&fields={q(fields)}&limit_page_length=0")
rows = r.get("message", [])
s, ppl = call("GET", f"/api/resource/FOLK%20Users?fields={q(json.dumps(['name','full_name']))}&limit_page_length=0")
by_name = {p["full_name"]: p["name"] for p in ppl["data"]}
ok = dup = bad = 0
for row in rows:
    doc = {
        "event_code": row["event_code"], "attendance_date": row["attendance_date"],
        "person": row["parent"], "marked_by": by_name.get(row.get("marked_by") or "", None),
        "ts": row.get("ts"),
    }
    s, r = call("POST", "/api/resource/FOLK%20Attendance", doc)
    if s == 200: ok += 1
    elif "Duplicate" in json.dumps(r) or s == 409: dup += 1
    else: bad += 1; print("! row failed", doc, r)
print(f"attendance copy: created={ok} already_there={dup} failed={bad} (source rows={len(rows)})")

# 6. Verify
for dt in ("FOLK Users", "FOLK Event", "FOLK Attendance"):
    s, r = call("GET", f"/api/method/frappe.client.get_count?doctype={q(dt)}")
    print(f"count {dt}: {r.get('message')}")
