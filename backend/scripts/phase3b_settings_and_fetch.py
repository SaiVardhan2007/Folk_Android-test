"""Adds FOLK Attendance.person_mob / marked_by_mob (auto-filled) and FOLK Settings switches. Re-runnable."""
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


def add_fields(doctype, specs, after_field):
    s, d = call("GET", "/api/resource/DocType/" + doctype.replace(" ", "%20"))
    doc = d["data"]; fields = doc["fields"]; have = {f["fieldname"] for f in fields}
    idx = next((i for i, f in enumerate(fields) if f["fieldname"] == after_field), len(fields) - 1)
    changed = False
    for spec in specs:
        if spec["fieldname"] not in have:
            idx += 1; fields.insert(idx, spec); changed = True; print("+", doctype, spec["fieldname"])
    if changed:
        s, r = call("PUT", "/api/resource/DocType/" + doctype.replace(" ", "%20"), doc)
        print("saved" if s == 200 else f"! {s} {r}")
    else:
        print("=", doctype, "already up to date")


add_fields("FOLK Attendance", [
    {"fieldname": "person_mob", "label": "Person Mobile", "fieldtype": "Data", "fetch_from": "person.mob_no", "read_only": 1},
    {"fieldname": "marked_by_mob", "label": "Marked By Mobile", "fieldtype": "Data", "fetch_from": "marked_by.mob_no", "read_only": 1},
], "marked_by_name")

add_fields("FOLK Settings", [
    {"fieldname": "offline_queue_enabled", "label": "Offline check-in queue", "fieldtype": "Check", "default": "0",
     "description": "When on, check-ins made without signal are saved on the phone and sent later."},
    {"fieldname": "auto_approve_signups", "label": "Approve new sign-ups automatically", "fieldtype": "Check", "default": "0",
     "description": "When off, a self sign-up stays inactive until an admin enables the account."},
    {"fieldname": "whatsapp_enabled", "label": "Send WhatsApp message on new registration", "fieldtype": "Check", "default": "0"},
    {"fieldname": "message_templates", "label": "Message templates (JSON)", "fieldtype": "Long Text"},
], "current_event")

# Backfill existing attendance rows
s, rows = call("GET", "/api/resource/FOLK%20Attendance?fields=%5B%22name%22%2C%22person%22%2C%22marked_by%22%5D&limit_page_length=0")
s, ppl = call("GET", "/api/resource/FOLK%20Users?fields=%5B%22name%22%2C%22mob_no%22%5D&limit_page_length=0")
mob = {p["name"]: p["mob_no"] for p in ppl["data"]}
for r in rows["data"]:
    patch = {"person_mob": mob.get(r["person"], ""), "marked_by_mob": mob.get(r["marked_by"], "")}
    s, _ = call("PUT", "/api/resource/FOLK%20Attendance/" + r["name"].replace(" ", "%20"), patch)
    print("backfilled", r["name"], s)
