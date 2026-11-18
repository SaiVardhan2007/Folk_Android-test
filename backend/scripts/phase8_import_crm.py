"""Moves the old CRM (Supabase export) into ERPNext. Safe to re-run: anything already there is skipped.

  python3 -I phase8_import_crm.py              dry run: writes NOTHING, prints the plan, saves ~/crm-export/import_plan.json
  python3 -I phase8_import_crm.py --commit     really imports (back up ERPNext first)

What goes where (decided with the owner):
  master_contacts (+ details from every registration source)  -> FOLK Users   (Public contacts)
  festival_events / event_sources                              -> FOLK Event   (4 events)
  registrations, krishnashtami_registrations, feedback_contacts, contacts_register -> FOLK Registration
  contact_assignments, krishnashtami_contact_assignments, feedback_contact_assignments (real call outcomes only) -> FOLK Call Log
Not imported: contact_operators (they sign up themselves), master_contact_assignments (later, on request), master_contact_checkins (test data),
audit_logs, krishnashtami_registration_prasadam, empty tables.
"""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.expanduser("~/crm-export/data")
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json",
     "User-Agent": "folk-import/1.0", "Accept": "application/json"}
q = urllib.parse.quote


def call(method, path, body=None, tries=4):
    for attempt in range(tries):
        req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            txt = e.read().decode()[:600]
            if e.code in (429, 502, 503, 504) and attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return e.code, {"error": txt}
        except Exception as e:  # network blip
            if attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return 0, {"error": str(e)}


def load(name):
    return json.load(open(os.path.join(DATA, name + ".json")))


def phone(raw):
    d = "".join(ch for ch in str(raw or "") if ch.isdigit())
    if len(d) == 12 and d.startswith("91"): d = d[2:]
    if len(d) == 11 and d.startswith("0"): d = d[1:]
    return d if len(d) == 10 and d[0] in "6789" else None


def ist(ts):
    if not ts: return None
    t = datetime.strptime(ts[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S") + timedelta(hours=5, minutes=30)  # source times are UTC
    return t.strftime("%Y-%m-%d %H:%M:%S")


BLANK = {"", "na", "n/a", "nil", "none", "-", "null"}
def txt(v, n=140):
    v = " ".join(str(v or "").split())
    return "" if v.lower() in BLANK else v[:n]


# ---------------------------------------------------------------- events
EVENTS = {
    "RATHAYATRA-2026": "Rathayatra 2026", "KRISHNASHTAMI-2026": "Krishnashtami 2026",
    "FEEDBACK": "Feedback Contact", "CONTACTS-REG": "Contacts Register",
}
SOURCE_EVENT = {"rathayatra": "RATHAYATRA-2026", "krishnashtami": "KRISHNASHTAMI-2026", "feedback_contacts": "FEEDBACK", "contacts_register": "CONTACTS-REG"}

# ---------------------------------------------------------------- load
masters = load("master_contacts")
regs = load("registrations"); krs = load("krishnashtami_registrations")
fbs = load("feedback_contacts"); crs = load("contacts_register")
slots = {x["id"]: x["slot_time"] for x in load("volunteer_slots")}
services = {x["id"]: x["name"] for x in load("services")}
skill_name = {x["id"]: x["name"] for x in load("skills")}
ops = {x["id"]: x for x in load("contact_operators")}

skipped = {"people": [], "registrations": [], "call_logs": []}

# per-phone extra details, later sources overwrite earlier ones only when they have a value
extra = {}
def put(ph, **kw):
    e = extra.setdefault(ph, {"skills": set(), "interests": set()})
    for k, v in kw.items():
        if k in ("skills", "interests"): e[k].update(v)
        elif v not in (None, "", 0): e[k] = v

reg_skill_ids = {}
for row in load("registration_skills"): reg_skill_ids.setdefault(row["registration_id"], set()).add(row["skill_id"])
for row in load("krishnashtami_registration_skills"): reg_skill_ids.setdefault(row["registration_id"], set()).add(row["skill_id"])

OCC = {"student": "Student", "working": "Working", "business": "Business", "others": "Others", "job search": "Job Search"}
def occupation(v):
    v = txt(v).lower()
    if not v: return ""
    return OCC.get(v, "")  # free text (Software, Civil engineer ...) is NOT guessed: it is kept in comments instead

for r in sorted(regs, key=lambda x: x["created_at"]):
    p = phone(r["phone"])
    if p: put(p, pg_name=txt(r.get("pg_name")), occupation=occupation(r.get("occupation")), skills={skill_name[s] for s in reg_skill_ids.get(r["id"], []) if s in skill_name})
for r in sorted(krs, key=lambda x: x["created_at"]):
    p = phone(r["phone"])
    if p: put(p, pg_name=txt(r.get("pg_name")), occupation=occupation(r.get("occupation")), skills={skill_name[s] for s in reg_skill_ids.get(r["id"], []) if s in skill_name})
for r in sorted(fbs, key=lambda x: x["created_at"]):
    p = phone(r["phone"])
    if p:
        put(p, current_stay=r.get("current_stay") or "", feedback=r.get("feedback") if r.get("feedback") in ("Excellent", "Good") else "",
            branch=txt(r.get("branch"), 40), skills=set(r.get("skills") or []),
            interests={"Online workshop"} if r.get("interested_online_workshop") else set())
for r in sorted(crs, key=lambda x: x["created_at"]):
    p = phone(r["phone"])
    if p:
        put(p, current_stay=r.get("current_stay") or "", pg_name=txt(r.get("pg_name")), profession=txt(r.get("profession")), comments=txt(r.get("comments"), 400),
            skills=set(r.get("skills") or []),
            interests={n for n, on in (("Online workshop", r.get("interested_online_workshop")), ("Bhagavad Gita", r.get("interested_bhagavad_gita"))) if on})

LEVEL = {"level-1": "AOMC", "level-2": "Folk Foundation", "level-3": "Folk Prelims", "level-4": "Enhance"}
GENDER = {"Male": "M", "Female": "F"}

people = {}
for m in sorted(masters, key=lambda x: x["created_at"]):
    p = phone(m["phone"])
    if not p:
        skipped["people"].append({"phone": m["phone"], "name": m["name"], "why": "invalid mobile number"}); continue
    e = extra.get(p, {"skills": set(), "interests": set()})
    prof = txt(m.get("company_college")) or e.get("profession", "")
    if e.get("branch") and prof and e["branch"].lower() not in prof.lower(): prof = f"{prof} ({e['branch']})"
    age = m.get("age")
    doc = {
        "doctype": "FOLK Users", "mob_no": p, "full_name": txt(m["name"], 100) or p, "gender": GENDER.get(m.get("gender"), ""),
        "level": LEVEL.get(m.get("level"), ""), "occupation": e.get("occupation", ""), "profession": prof, "pg_name": e.get("pg_name", ""),
        "venue": txt(m.get("area_of_stay"), 200), "event_code": SOURCE_EVENT.get(m.get("latest_registration_source"), ""),
        "user_tag": "Public", "is_active": 1, "registered_by": "Imported from old CRM",
        "age": age if isinstance(age, int) and 1 <= age <= 120 else None, "current_stay": e.get("current_stay", ""),
        "skills": ", ".join(sorted(e["skills"]))[:200], "interests": ", ".join(sorted(e["interests"]))[:200],
        "chanting_rounds": m.get("chanting") or None, "feedback": e.get("feedback", ""), "comments": e.get("comments", ""),
        "registered_on": ist(m["created_at"])[:10], "attendance_count": m.get("classes_attended") or 0, "not_interested": 1 if m.get("is_not_interested") else 0,
    }
    people[p] = {k: v for k, v in doc.items() if v not in ("", None)}

# ---------------------------------------------------------------- registrations
registrations = {}   # (event, phone) -> doc
def add_reg(event, ph_raw, created, **kw):
    p = phone(ph_raw)
    if not p or p not in people:
        skipped["registrations"].append({"event": event, "phone": ph_raw, "why": "no valid contact for this number"}); return
    doc = {"doctype": "FOLK Registration", "event_code": event, "_phone": p, "registered_at": ist(created)}
    doc.update({k: v for k, v in kw.items() if v not in ("", None)})
    registrations[(event, p)] = doc  # a later row for the same person+event replaces the earlier one

def donation(v): return "Opted to Donate" if v == "User Opted to Donate" else ("Pending" if v else "")
for r in sorted(regs, key=lambda x: x["created_at"]):
    add_reg("RATHAYATRA-2026", r["phone"], r["created_at"], registration_no=r.get("registration_no"), volunteer=1 if r.get("interested_to_volunteer") else 0,
            volunteer_slot=slots.get(r.get("volunteer_slot_id"), ""), service=services.get(r.get("service_id"), ""), dinner=1 if r.get("interested_to_dinner") else 0,
            donation=donation(r.get("donation_status")), transport_required=1 if r.get("transportation_required") == "Yes" else 0)
for r in sorted(krs, key=lambda x: x["created_at"]):
    add_reg("KRISHNASHTAMI-2026", r["phone"], r["created_at"], registration_no=r.get("registration_no"), volunteer=1 if r.get("interested_to_volunteer") else 0,
            volunteer_slot=slots.get(r.get("volunteer_slot_id"), ""), service=services.get(r.get("service_id"), ""), dinner=1 if r.get("interested_to_dinner") else 0,
            donation=donation(r.get("donation_status")), transport_required=1 if r.get("transportation_required") == "Yes" else 0, standard=txt(r.get("standard"), 40))
for r in sorted(fbs, key=lambda x: x["created_at"]): add_reg("FEEDBACK", r["phone"], r["created_at"])
for r in sorted(crs, key=lambda x: x["created_at"]): add_reg("CONTACTS-REG", r["phone"], r["created_at"])

# ---------------------------------------------------------------- call logs (real outcomes only)
STATUS = {"Coming": "Joining the session", "Next Week": "Next Week will join", "Callback Required": "Need to Call Again",
          "Not Coming": "Not Coming", "Not Answered": "Not Answered", "Not Interested": "Not Interested", "Not in Hyderabad": "Out of Station"}
NOT_A_CALL = {"Pending", "Assigned"}
call_logs = []
def add_calls(table, event, reg_table, reg_key):
    by_id = {x["id"]: x for x in reg_table}
    for a in load(table):
        if a["status"] in NOT_A_CALL: continue
        reg = by_id.get(a[reg_key]); p = phone(reg["phone"]) if reg else None
        if not p or p not in people:
            skipped["call_logs"].append({"id": a["id"], "why": "contact not found"}); continue
        op = ops.get(a.get("operator_id"))
        mapped = STATUS.get(a["status"])
        note = " | ".join(x for x in (txt(a.get("remarks"), 400), txt(a.get("notes"), 400)) if x)
        if not mapped:
            mapped = "Others"; note = f"Earlier status: {a['status']}" + (f" | {note}" if note else "")
        call_logs.append({"doctype": "FOLK Call Log", "client_ref": a["id"], "_phone": p, "event_code": event, "status": mapped, "note": note,
                          "called_at": ist(a.get("called_at") or a.get("updated_at") or a["assigned_at"]),
                          "legacy_caller": f"{op['name']} ({op.get('phone') or 'no number'})" if op else ""})
add_calls("contact_assignments", "RATHAYATRA-2026", regs, "registration_id")
add_calls("krishnashtami_contact_assignments", "KRISHNASHTAMI-2026", krs, "registration_id")
add_calls("feedback_contact_assignments", "FEEDBACK", fbs, "feedback_contact_id")

# ---------------------------------------------------------------- plan
def count_by(rows, k):
    out = {}
    for r in rows: out[r.get(k, "")] = out.get(r.get(k, ""), 0) + 1
    return dict(sorted(out.items(), key=lambda kv: -kv[1]))

plan = {
    "events_to_create": EVENTS,
    "people": {"total": len(people), "by_level": count_by(people.values(), "level"), "by_gender": count_by(people.values(), "gender"),
               "with_age": sum(1 for p in people.values() if "age" in p), "with_skills": sum(1 for p in people.values() if "skills" in p),
               "not_interested": sum(1 for p in people.values() if p.get("not_interested")), "skipped": skipped["people"]},
    "registrations": {"total": len(registrations), "by_event": count_by([{"e": k[0]} for k in registrations], "e"), "skipped": skipped["registrations"]},
    "call_logs": {"total": len(call_logs), "by_event": count_by(call_logs, "event_code"), "by_status": count_by(call_logs, "status"),
                  "with_earlier_caller": sum(1 for c in call_logs if c["legacy_caller"]), "skipped": skipped["call_logs"]},
    "samples": {"person": next(iter(people.values())), "registration": next(iter(registrations.values())), "call_log": call_logs[0]},
}
json.dump(plan, open(os.path.expanduser("~/crm-export/import_plan.json"), "w"), indent=1, default=str)
print(json.dumps({k: v for k, v in plan.items() if k != "samples"}, indent=1, default=str)[:3500])

if not COMMIT:
    print("\nDRY RUN: nothing was written. Re-run with --commit to import.")
    sys.exit(0)

# ---------------------------------------------------------------- commit
def existing(doctype, field):
    s, r = call("GET", f"/api/resource/{q(doctype)}?fields={q(json.dumps([field]))}&limit_page_length=0")
    assert s == 200, r
    return {x[field] for x in r["data"]}

def run(items, fn, label, workers=6):
    ok = fail = 0
    with ThreadPoolExecutor(workers) as ex:
        for done, res in enumerate(ex.map(fn, items), 1):
            if res: ok += 1
            else: fail += 1
            if done % 250 == 0: print(f"  {label}: {done}/{len(items)}", flush=True)
    print(f"{label}: {ok} added, {fail} failed")
    return fail

for code, name in EVENTS.items():
    s, r = call("POST", "/api/resource/FOLK%20Event", {"code": code, "event_name": name})
    print("event", code, "created" if s == 200 else ("exists" if s == 409 or "Duplicate" in str(r) else f"FAILED {s} {r}"))

have = existing("FOLK Users", "mob_no")
todo = [d for p, d in people.items() if p not in have]
print(f"people: {len(have)} already in ERPNext, {len(todo)} to add")
def add_person(d):
    s, r = call("POST", "/api/resource/FOLK%20Users", d)
    if s != 200: print("  ! person", d["mob_no"], s, str(r)[:200])
    return s == 200
run(todo, add_person, "people")

s, r = call("GET", f"/api/resource/FOLK%20Users?fields={q(json.dumps(['name', 'mob_no']))}&limit_page_length=0")
pid = {x["mob_no"]: x["name"] for x in r["data"]}

have_reg = existing("FOLK Registration", "name")
regs_todo = []
for (event, p), d in registrations.items():
    if f"{event}-{pid[p]}" in have_reg: continue
    d = {k: v for k, v in d.items() if k != "_phone"}; d["person"] = pid[p]; regs_todo.append(d)
print(f"registrations: {len(have_reg)} already there, {len(regs_todo)} to add")
def add_reg_doc(d):
    s, r = call("POST", "/api/resource/FOLK%20Registration", d)
    if s != 200: print("  ! registration", d["event_code"], d["person"], s, str(r)[:200])
    return s == 200
run(regs_todo, add_reg_doc, "registrations")

have_ref = existing("FOLK Call Log", "client_ref")
logs_todo = []
for d in call_logs:
    if d["client_ref"] in have_ref: continue
    doc = {k: v for k, v in d.items() if k != "_phone"}
    doc["person"] = pid[d["_phone"]]
    logs_todo.append({k: v for k, v in doc.items() if v not in ("", None)})
print(f"call logs: {len(have_ref)} already there, {len(logs_todo)} to add")
def add_log(d):
    s, r = call("POST", "/api/resource/FOLK%20Call%20Log", d)
    if s != 200: print("  ! call log", d["client_ref"], s, str(r)[:200])
    return s == 200
run(logs_todo, add_log, "call logs")
print("DONE")
