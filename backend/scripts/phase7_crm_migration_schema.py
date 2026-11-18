"""Schema for moving the old CRM (Supabase) data in. Re-runnable.

- FOLK Users: age, current_stay, skills, interests, chanting_rounds, feedback, comments, not_interested;
  level gets AOMC + Enhance, occupation gets Business + Others.
- FOLK Registration: ONE record per person per event (all festivals / sources).
- FOLK Call Log: coordinator no longer required + legacy_caller (calls made in the old system by people who have no account yet).
- FOLK Activity Log: one log of every action by any user / coordinator / admin.
"""
import json, os, urllib.parse, urllib.request, urllib.error

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


q = urllib.parse.quote
PERM = [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}]

REGISTRATION = {
    "doctype": "DocType", "name": "FOLK Registration", "module": "Custom", "custom": 1,
    # One record per person per event: registering twice for the same event can never create a second row.
    "autoname": "format:{event_code}-{person}", "naming_rule": "Expression",
    "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0, "permissions": PERM,
    "fields": [
        {"fieldname": "event_code", "label": "Event", "fieldtype": "Link", "options": "FOLK Event", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person", "label": "Person", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person_name", "label": "Name", "fieldtype": "Data", "fetch_from": "person.full_name", "read_only": 1, "in_list_view": 1},
        {"fieldname": "person_mob", "label": "Mobile", "fieldtype": "Data", "fetch_from": "person.mob_no", "read_only": 1, "search_index": 1},
        {"fieldname": "registration_no", "label": "Registration No", "fieldtype": "Data", "search_index": 1},
        {"fieldname": "registered_at", "label": "Registered At", "fieldtype": "Datetime", "search_index": 1},
        {"fieldname": "volunteer", "label": "Wants to volunteer", "fieldtype": "Check", "default": "0"},
        {"fieldname": "volunteer_slot", "label": "Volunteer slot", "fieldtype": "Data"},
        {"fieldname": "service", "label": "Service", "fieldtype": "Data"},
        {"fieldname": "dinner", "label": "Dinner", "fieldtype": "Check", "default": "0"},
        {"fieldname": "donation", "label": "Donation", "fieldtype": "Select", "options": "\nPending\nOpted to Donate"},
        {"fieldname": "transport_required", "label": "Transport required", "fieldtype": "Check", "default": "0"},
        {"fieldname": "standard", "label": "Year / standard", "fieldtype": "Data"},
    ],
}

ACTIVITY = {
    "doctype": "DocType", "name": "FOLK Activity Log", "module": "Custom", "custom": 1,
    "autoname": "hash", "naming_rule": "Random",
    "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0, "permissions": PERM,
    "fields": [
        {"fieldname": "at", "label": "At", "fieldtype": "Datetime", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "user_id", "label": "User ID", "fieldtype": "Data", "search_index": 1},
        {"fieldname": "user_name", "label": "User", "fieldtype": "Data", "in_list_view": 1},
        {"fieldname": "role", "label": "Role", "fieldtype": "Data", "in_list_view": 1, "search_index": 1},
        {"fieldname": "action", "label": "Action", "fieldtype": "Data", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "target", "label": "About", "fieldtype": "Data", "in_list_view": 1},
        {"fieldname": "details", "label": "Details", "fieldtype": "Small Text"},
    ],
}

USER_FIELDS = [
    {"fieldname": "age", "label": "Age", "fieldtype": "Int"},
    {"fieldname": "current_stay", "label": "Staying", "fieldtype": "Select", "options": "\nWith Parents\nIn Hostel"},
    {"fieldname": "skills", "label": "Skills", "fieldtype": "Data", "description": "Comma separated, e.g. Singing, Photography"},
    {"fieldname": "interests", "label": "Interests", "fieldtype": "Data", "description": "Comma separated, e.g. Online workshop, Bhagavad Gita"},
    {"fieldname": "chanting_rounds", "label": "Chanting rounds", "fieldtype": "Int"},
    {"fieldname": "feedback", "label": "Feedback", "fieldtype": "Select", "options": "\nExcellent\nGood"},
    {"fieldname": "comments", "label": "Comments", "fieldtype": "Small Text"},
    {"fieldname": "not_interested", "label": "Not interested", "fieldtype": "Check", "default": "0", "search_index": 1},
]
LEVEL_OPTIONS = "\nAOMC\nFolk Foundation\nFolk Prelims\nEnhance"
OCCUPATION_OPTIONS = "\nStudent\nJob Search\nWorking\nBusiness\nOthers"


def exists(name):
    s, _ = call("GET", "/api/resource/DocType/" + q(name))
    return s == 200


for d in (REGISTRATION, ACTIVITY):
    if exists(d["name"]):
        print("=", d["name"], "already exists")
    else:
        s, r = call("POST", "/api/resource/DocType", d)
        print(("+ created " if s == 200 else f"! FAILED {s} ") + d["name"], "" if s == 200 else r)

# FOLK Users
s, r = call("GET", "/api/resource/DocType/FOLK%20Users")
doc = r["data"]; fields = doc["fields"]; have = {f["fieldname"] for f in fields}
changed = False
idx = next(i for i, f in enumerate(fields) if f["fieldname"] == "fg_mob_no")
for f in USER_FIELDS:
    if f["fieldname"] not in have:
        idx += 1; fields.insert(idx, f); changed = True; print("+ FOLK Users." + f["fieldname"])
for f in fields:
    if f["fieldname"] == "level" and f.get("options") != LEVEL_OPTIONS:
        f["options"] = LEVEL_OPTIONS; changed = True; print("~ FOLK Users.level options")
    if f["fieldname"] == "occupation" and f.get("options") != OCCUPATION_OPTIONS:
        f["options"] = OCCUPATION_OPTIONS; changed = True; print("~ FOLK Users.occupation options")
if changed:
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", doc)
    print("FOLK Users saved" if s == 200 else f"! {s} {r}")

# FOLK Call Log
s, r = call("GET", "/api/resource/DocType/FOLK%20Call%20Log")
doc = r["data"]; fields = doc["fields"]; changed = False
for f in fields:
    if f["fieldname"] == "coordinator" and f.get("reqd"):
        f["reqd"] = 0; changed = True; print("~ FOLK Call Log.coordinator not required")
if "legacy_caller" not in {f["fieldname"] for f in fields}:
    i = next(i for i, f in enumerate(fields) if f["fieldname"] == "coordinator_name")
    fields.insert(i + 1, {"fieldname": "legacy_caller", "label": "Earlier caller", "fieldtype": "Data",
                          "description": "Name and mobile of the caller in the old system (they had no account here)"})
    changed = True; print("+ FOLK Call Log.legacy_caller")
if changed:
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Call%20Log", doc)
    print("FOLK Call Log saved" if s == 200 else f"! {s} {r}")
