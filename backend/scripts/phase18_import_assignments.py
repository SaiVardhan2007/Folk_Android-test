"""Brings the old CRM's contact assignments (master_contact_assignments) into the app. Re-runnable: anything already there is skipped.

  python3 -I scripts/phase18_import_assignments.py                     dry run for the current event: writes NOTHING
  python3 -I scripts/phase18_import_assignments.py --event=FOLK        dry run for a chosen event code
  python3 -I scripts/phase18_import_assignments.py --commit            really writes

From ~/crm-export/data:
  - every call that was actually made (status other than "assigned")       -> FOLK Call Log (history; client_ref = old id, so never twice)
  - each contact's LATEST assignment, if still not called ("assigned")     -> FOLK Assignment for the event, status "Not Done",
                                                                              same coordinator, original assigned time
Pending calls are skipped when: the contact is not Public here (Not Interested / staff), the old CRM marked them not interested,
the caller is not a Coordinator here (run phase16 first), or the contact already has an assignment for this event (the app's is kept).
No WhatsApp alerts are sent.
"""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error
from collections import Counter, defaultdict
from datetime import datetime, timedelta

COMMIT = "--commit" in sys.argv
EVENT_ARG = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--event=")), "")
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.expanduser("~/crm-export/data")
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-import/1.0", "Accept": "application/json"}
q = urllib.parse.quote
PENDING = "Not Done"
STATUS = {"Coming": "Joining the session", "Next Week": "Next Week will join", "Callback Required": "Need to Call Again",
          "Not Coming": "Not Coming", "Not Answered": "Not Answered", "Not Interested": "Not Interested", "Not in Hyderabad": "Out of Station"}


def call(method, path, body=None, tries=4):
    for attempt in range(tries):
        req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code in (429, 502, 503, 504) and attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return e.code, {"error": e.read().decode()[:800]}
        except Exception as e:
            if attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return 0, {"error": str(e)}


def get_all(doctype, fields, filters=None):
    s, r = call("GET", f"/api/resource/{q(doctype)}?fields=" + q(json.dumps(fields)) + ("&filters=" + q(json.dumps(filters)) if filters else "") + "&limit_page_length=0")
    if s != 200: raise SystemExit(f"! reading {doctype} failed {s} {r}")
    return r["data"]


def phone(raw):
    d = "".join(ch for ch in str(raw or "") if ch.isdigit())
    if len(d) == 12 and d.startswith("91"): d = d[2:]
    if len(d) == 11 and d.startswith("0"): d = d[1:]
    return d if len(d) == 10 and d[0] in "6789" else None


def ist(ts):
    return (datetime.strptime(ts[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S") + timedelta(hours=5, minutes=30)).strftime("%Y-%m-%d %H:%M:%S")


load = lambda n: json.load(open(os.path.join(DATA, n + ".json")))
asg_old = load("master_contact_assignments")
masters = {m["id"]: m for m in load("master_contacts")}
ops = {o["id"]: o for o in load("contact_operators")}

events = get_all("FOLK Event", ["name", "event_name", "is_current", "is_list"])
event = EVENT_ARG or next((e["name"] for e in events if e["is_current"] and not e["is_list"]), "")
if event not in {e["name"] for e in events}: raise SystemExit(f"! unknown event '{event}'. Codes: {[e['name'] for e in events]}")
print(("COMMIT" if COMMIT else "DRY RUN (nothing is written)") + f" | event: {event} ({next(e['event_name'] for e in events if e['name'] == event)})")

people = {p["mob_no"]: p for p in get_all("FOLK Users", ["name", "mob_no", "full_name", "user_tag", "is_active"])}
coord_of = {}  # old operator id -> FOLK Users row (Coordinator/Admin)
for oid, o in ops.items():
    p = people.get(phone(o.get("phone")) or "-")
    if p and p["user_tag"] in ("Coordinator", "Admin"): coord_of[oid] = p
legacy = lambda o: f"{o['name']} ({o.get('phone') or 'no number'})" if o else ""

# ---------------------------------------------------------------- call history
logs, skip_log = [], Counter()
for a in asg_old:
    if a["status"] == "assigned": continue
    m = masters.get(a["master_contact_id"]); p = people.get(phone(m["phone"]) if m else "-")
    if not p: skip_log["contact not found here"] += 1; continue
    status = STATUS.get(a["status"]); note = " ".join(str(a.get("comments") or "").split())[:1000]
    if not status: status, note = "Others", f"Earlier status: {a['status']}" + (f" | {note}" if note else "")
    co = coord_of.get(a["operator_id"])
    logs.append({"doctype": "FOLK Call Log", "client_ref": a["id"], "person": p["name"], "coordinator": co["name"] if co else None,
                 "event_code": event, "status": status, "note": note, "called_at": ist(a["updated_at"] or a["assigned_at"]),
                 "legacy_caller": legacy(ops.get(a["operator_id"]))})
have_ref = {x["client_ref"] for x in get_all("FOLK Call Log", ["client_ref"])}  # all refs: a filter listing ~600 ids is too long for a URL
new_logs = [l for l in logs if l["client_ref"] not in have_ref]

# ---------------------------------------------------------------- pending calls (latest assignment per contact)
latest = {}
for a in sorted(asg_old, key=lambda x: x["assigned_at"]): latest[a["master_contact_id"]] = a
existing = {x["person"]: x for x in get_all("FOLK Assignment", ["name", "person", "coordinator_name", "status"], [["event_code", "=", event]])}
pend, skip = [], defaultdict(list)
for mid, a in latest.items():
    if a["status"] != "assigned": continue
    m = masters.get(mid); p = people.get(phone(m["phone"]) if m else "-")
    who = f"{m['name'] if m else '?'} {m['phone'] if m else ''}"
    if not p: skip["contact not found here"].append(who); continue
    if m.get("is_not_interested"): skip["not interested in old CRM"].append(who); continue
    if (p["user_tag"] or "Public") != "Public": skip[f"role here is {p['user_tag']}"].append(who); continue
    co = coord_of.get(a["operator_id"])
    if not co: skip["caller is not a coordinator here: " + legacy(ops.get(a["operator_id"]))].append(who); continue
    if p["name"] in existing: skip["already assigned in the app for this event"].append(who); continue
    pend.append({"doctype": "FOLK Assignment", "person": p["name"], "coordinator": co["name"], "event_code": event, "status": PENDING,
                 "is_follow_up": 0, "assigned_at": ist(a["assigned_at"]), "_co": co})

# ---------------------------------------------------------------- plan
print(f"\nCall history: {len(logs)} real calls | new: {len(new_logs)} | already imported: {len(logs) - len(new_logs)} | skipped: {dict(skip_log)}")
print(f"  by status: {dict(Counter(l['status'] for l in new_logs))}")
print(f"  linked to a coordinator: {sum(1 for l in new_logs if l['coordinator'])}")
print(f"\nPending calls to assign: {len(pend)}")
per = Counter((x["_co"]["full_name"], x["_co"]["mob_no"], x["_co"]["is_active"]) for x in pend)
for (n, mob, active), k in sorted(per.items(), key=lambda t: -t[1]):
    print(f"  {k:4}  {n} ({mob})" + ("" if active else "   <- account DISABLED: these calls will wait until it is enabled"))
print(f"  assigned on: {dict(sorted(Counter(x['assigned_at'][:10] for x in pend).items()))}")
for why, who in skip.items():
    print(f"  skipped {len(who):4}  {why}")
plan = {"event": event, "new_call_logs": len(new_logs), "pending": len(pend), "skipped": {k: v for k, v in skip.items()}}
json.dump(plan, open(os.path.expanduser("~/crm-export/assignments_plan.json"), "w"), indent=1)
print("  (full list of skipped contacts saved to ~/crm-export/assignments_plan.json)")

if not COMMIT:
    print("\nDry run only. Re-run with --commit to write."); sys.exit(0)

def insert_many(docs, what):
    done = 0
    for i in range(0, len(docs), 100):
        part = [{k: v for k, v in d.items() if not k.startswith("_") and v is not None} for d in docs[i:i + 100]]
        s, r = call("POST", "/api/method/frappe.client.insert_many", {"docs": part})
        if s == 200: done += len(part)
        else: print(f"  ! {what} {i + 1}-{i + len(part)}: {s} {str(r)[:300]}")
    print(f"  {what}: {done} of {len(docs)} written")

insert_many(new_logs, "call history")
insert_many(pend, "pending calls")
print("Done.")
