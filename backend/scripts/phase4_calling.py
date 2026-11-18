"""Calling system: FOLK Assignment + FOLK Call Log, and call_limit/auto_assign on FOLK Users. Re-runnable."""
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


PERM = [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}]

ASSIGNMENT = {
    "doctype": "DocType", "name": "FOLK Assignment", "module": "Custom", "custom": 1,
    # One record per contact + event: a contact can't be assigned twice for the same event.
    "autoname": "format:{person}-{event_code}", "naming_rule": "Expression",
    "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0, "permissions": PERM,
    "fields": [
        {"fieldname": "person", "label": "Contact", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person_name", "label": "Contact Name", "fieldtype": "Data", "fetch_from": "person.full_name", "read_only": 1, "in_list_view": 1},
        {"fieldname": "person_mob", "label": "Contact Mobile", "fieldtype": "Data", "fetch_from": "person.mob_no", "read_only": 1},
        {"fieldname": "coordinator", "label": "Coordinator", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "coordinator_name", "label": "Coordinator Name", "fieldtype": "Data", "fetch_from": "coordinator.full_name", "read_only": 1},
        {"fieldname": "event_code", "label": "Event", "fieldtype": "Link", "options": "FOLK Event", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "status", "label": "Status", "fieldtype": "Data", "default": "Not Done", "in_list_view": 1, "search_index": 1},
        {"fieldname": "note", "label": "Note", "fieldtype": "Small Text"},
        {"fieldname": "is_follow_up", "label": "Follow-up", "fieldtype": "Check", "default": "0", "search_index": 1},
        {"fieldname": "assigned_at", "label": "Assigned At", "fieldtype": "Datetime"},
        {"fieldname": "submitted_at", "label": "Last Submitted At", "fieldtype": "Datetime"},
    ],
}

CALL_LOG = {
    "doctype": "DocType", "name": "FOLK Call Log", "module": "Custom", "custom": 1,
    # Permanent record of every call outcome. client_ref is unique, so a retried submit can never create a second row.
    "autoname": "hash", "naming_rule": "Random",
    "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0, "permissions": PERM,
    "fields": [
        {"fieldname": "client_ref", "label": "Client Ref", "fieldtype": "Data", "unique": 1, "reqd": 1},
        {"fieldname": "person", "label": "Contact", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person_name", "label": "Contact Name", "fieldtype": "Data", "fetch_from": "person.full_name", "read_only": 1},
        {"fieldname": "person_mob", "label": "Contact Mobile", "fieldtype": "Data", "fetch_from": "person.mob_no", "read_only": 1, "search_index": 1},
        {"fieldname": "coordinator", "label": "Coordinator", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "coordinator_name", "label": "Coordinator Name", "fieldtype": "Data", "fetch_from": "coordinator.full_name", "read_only": 1},
        {"fieldname": "event_code", "label": "Event", "fieldtype": "Link", "options": "FOLK Event", "search_index": 1},
        {"fieldname": "status", "label": "Status", "fieldtype": "Data", "in_list_view": 1, "search_index": 1},
        {"fieldname": "note", "label": "Note", "fieldtype": "Small Text"},
        {"fieldname": "called_at", "label": "Called At", "fieldtype": "Datetime", "search_index": 1},
    ],
}


def exists(name):
    s, _ = call("GET", "/api/resource/DocType/" + name.replace(" ", "%20"))
    return s == 200


for d in (ASSIGNMENT, CALL_LOG):
    if exists(d["name"]):
        print("=", d["name"], "already exists")
    else:
        s, r = call("POST", "/api/resource/DocType", d)
        print(("+ created " if s == 200 else f"! FAILED {s} ") + d["name"], "" if s == 200 else r)

# Coordinator call settings on FOLK Users
s, r = call("GET", "/api/resource/DocType/FOLK%20Users")
doc = r["data"]; fields = doc["fields"]; have = {f["fieldname"] for f in fields}
idx = next(i for i, f in enumerate(fields) if f["fieldname"] == "fg_mob_no")
add = [
    {"fieldname": "call_limit", "label": "Call Limit", "fieldtype": "Int", "description": "Most contacts this coordinator can be given (blank = no limit)"},
    {"fieldname": "auto_assign", "label": "Auto Assign", "fieldtype": "Check", "default": "1", "description": "Include in automatic distribution of calls"},
]
changed = False
for f in add:
    if f["fieldname"] not in have:
        idx += 1; fields.insert(idx, f); changed = True; print("+ FOLK Users." + f["fieldname"])
if changed:
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", doc)
    print("saved" if s == 200 else f"! {s} {r}")
