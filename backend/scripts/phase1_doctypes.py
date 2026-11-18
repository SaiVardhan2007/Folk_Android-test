"""Phase 1: create FOLK Person + FOLK Attendance DocTypes, add is_current to FOLK Event.
Safe to re-run: skips anything that already exists. Reads backend/.dev.vars. Run: python3 -I scripts/phase1_doctypes.py
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
        BASE + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": AUTH, "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:600]}


def exists(doctype, name):
    s, _ = call("GET", f"/api/resource/{urllib.parse.quote(doctype)}/{urllib.parse.quote(name)}")
    return s == 200


PERM = [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "report": 1, "export": 1}]

PERSON = {
    "doctype": "DocType", "name": "FOLK Person", "module": "Custom", "custom": 1,
    "autoname": "field:mob_no", "naming_rule": "By fieldname",
    "title_field": "full_name", "search_fields": "full_name,mob_no",
    "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0,
    "permissions": PERM,
    "fields": [
        {"fieldname": "mob_no", "label": "Mobile", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1},
        {"fieldname": "full_name", "label": "Full Name", "fieldtype": "Data", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "gender", "label": "Gender", "fieldtype": "Select", "options": "\nM\nF"},
        {"fieldname": "level", "label": "Level", "fieldtype": "Select", "options": "\nFolk Foundation\nFolk Prelims", "in_list_view": 1, "search_index": 1},
        {"fieldname": "occupation", "label": "Occupation", "fieldtype": "Select", "options": "\nStudent\nJob Search\nWorking"},
        {"fieldname": "profession", "label": "Company / College", "fieldtype": "Data"},
        {"fieldname": "pg_name", "label": "PG / Residence", "fieldtype": "Data"},
        {"fieldname": "event_code", "label": "Registered Event", "fieldtype": "Link", "options": "FOLK Event"},
        {"fieldname": "user_tag", "label": "Role", "fieldtype": "Select", "options": "People\nCoordinator\nAdmin\nCaller", "default": "People", "in_list_view": 1, "search_index": 1},
        {"fieldname": "is_active", "label": "Active", "fieldtype": "Check", "default": "1"},
        {"fieldname": "stats_section", "label": "Attendance Summary", "fieldtype": "Section Break"},
        {"fieldname": "attendance_count", "label": "Attendance Count", "fieldtype": "Int", "default": "0", "read_only": 1, "in_list_view": 1},
        {"fieldname": "last_attended_on", "label": "Last Attended On", "fieldtype": "Date", "read_only": 1, "search_index": 1},
        {"fieldname": "registered_by", "label": "Registered By", "fieldtype": "Data", "read_only": 1},
        {"fieldname": "auth_section", "label": "Login (managed by the app, never shown)", "fieldtype": "Section Break", "collapsible": 1},
        {"fieldname": "password_hash", "label": "Password Hash", "fieldtype": "Data", "read_only": 1},
        {"fieldname": "reset_code_hash", "label": "Reset Code Hash", "fieldtype": "Data", "read_only": 1},
        {"fieldname": "reset_code_expires", "label": "Reset Code Expires", "fieldtype": "Datetime", "read_only": 1},
    ],
}

ATTENDANCE = {
    "doctype": "DocType", "name": "FOLK Attendance", "module": "Custom", "custom": 1,
    # One record per programme + date + person => duplicates are impossible at the DB level.
    "autoname": "format:{event_code}-{attendance_date}-{person}", "naming_rule": "Expression",
    "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0,
    "permissions": PERM,
    "fields": [
        {"fieldname": "event_code", "label": "Event", "fieldtype": "Link", "options": "FOLK Event", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "attendance_date", "label": "Date", "fieldtype": "Date", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person", "label": "Person", "fieldtype": "Link", "options": "FOLK Person", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person_name", "label": "Person Name", "fieldtype": "Data", "fetch_from": "person.full_name", "read_only": 1, "in_list_view": 1},
        {"fieldname": "marked_by", "label": "Marked By", "fieldtype": "Link", "options": "FOLK Person", "in_list_view": 1},
        {"fieldname": "ts", "label": "Marked At", "fieldtype": "Datetime"},
    ],
}


def create(doc):
    name = doc["name"]
    if exists("DocType", name):
        print(f"= {name}: already exists, skipped")
        return
    s, r = call("POST", "/api/resource/DocType", doc)
    print(("+ created " if s == 200 else f"! FAILED {s} ") + name, "" if s == 200 else r)


# FOLK Event must get is_current BEFORE Person links to it (it already exists, link is fine either way)
s, ev = call("GET", "/api/resource/DocType/FOLK%20Event")
if s != 200: raise SystemExit(f"cannot read FOLK Event: {s} {ev}")
fields = ev["data"]["fields"]
if not any(f["fieldname"] == "is_current" for f in fields):
    ev["data"]["fields"].append({"fieldname": "is_current", "label": "Is Current", "fieldtype": "Check", "default": "0", "in_list_view": 1})
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Event", ev["data"])
    print("+ FOLK Event.is_current added" if s == 200 else f"! FOLK Event update failed {s} {r}")
else:
    print("= FOLK Event.is_current already exists")

create(PERSON)
create(ATTENDANCE)
