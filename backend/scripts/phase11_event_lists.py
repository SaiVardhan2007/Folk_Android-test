"""Phase 11: separate always-open contact lists (Feedback Contact, Contacts Register) from real events.
Adds FOLK Event.is_list (Check) and sets it on the two lists the CRM import created as events.
Nothing is deleted or moved: registrations, calls and people keep their event_code. Safe to re-run.
Run: python3 -I scripts/phase11_event_lists.py
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
LISTS = ["FEEDBACK", "CONTACTS-REG"]


def call(method, path, body=None):
    req = urllib.request.Request(
        BASE + path, method=method, data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": AUTH, "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:600]}


s, dt = call("GET", "/api/resource/DocType/FOLK%20Event")
if s != 200: raise SystemExit(f"cannot read FOLK Event: {s} {dt}")
if not any(f["fieldname"] == "is_list" for f in dt["data"]["fields"]):
    dt["data"]["fields"].append({"fieldname": "is_list", "label": "Is Contact List", "fieldtype": "Check", "default": "0", "in_list_view": 1,
                                 "description": "Always-open list (e.g. Feedback), not a dated event"})
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Event", dt["data"])
    print("+ FOLK Event.is_list added" if s == 200 else f"! failed {s} {r}")
    if s != 200: raise SystemExit(1)
else:
    print("= FOLK Event.is_list already exists")

for code in LISTS:
    s, r = call("PUT", f"/api/resource/FOLK%20Event/{urllib.parse.quote(code)}", {"is_list": 1, "is_current": 0})
    print(f"{code}: marked as contact list" if s == 200 else f"{code}: skipped ({s}) {str(r)[:120]}")
