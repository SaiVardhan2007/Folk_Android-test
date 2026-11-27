"""Dropdown lists stored by ID: College / Company, Branch, Skill, Interest. Re-runnable, only adds.

  python3 -I scripts/phase20_option_lists.py            dry run: writes NOTHING
  python3 -I scripts/phase20_option_lists.py --commit   really writes

Each list is its own DocType. A value gets a random ID that never changes, and an editable Title.
People store only the ID (Link fields), so editing a Title in ERPNext changes it for everyone at once.
  FOLK College  <- FOLK Users.college      (Link)
  FOLK Branch   <- FOLK Users.branch       (Link)
  FOLK Skill    <- FOLK Users.skill_list    (Table MultiSelect, child "FOLK User Skill")
  FOLK Interest <- FOLK Users.interest_list (Table MultiSelect, child "FOLK User Interest")
The old text fields (profession, skills, interests) are left untouched here; phase21 moves their values over.
"""
import json, os, sys, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
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


def master(name, desc):
    return {
        "doctype": "DocType", "name": name, "module": "Custom", "custom": 1, "description": desc,
        "autoname": "hash", "naming_rule": "Random",  # the ID never changes; the Title is what people see and edit
        "title_field": "title", "show_title_field_in_link": 1, "search_fields": "title",
        "sort_field": "title", "sort_order": "ASC", "track_changes": 1, "quick_entry": 1, "permissions": PERM,
        "fields": [{"fieldname": "title", "label": "Title", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1, "in_standard_filter": 1}],
    }


def child(name, field, target):
    return {
        "doctype": "DocType", "name": name, "module": "Custom", "custom": 1, "istable": 1, "editable_grid": 1,
        "fields": [{"fieldname": field, "label": target.replace("FOLK ", ""), "fieldtype": "Link", "options": target, "reqd": 1, "in_list_view": 1}],
    }


DOCTYPES = [
    master("FOLK College", "College or company names (FOLK Users.college)."),
    master("FOLK Branch", "Branch of study, e.g. CSE (FOLK Users.branch)."),
    master("FOLK Skill", "Skills (FOLK Users.skill_list)."),
    master("FOLK Interest", "Interests (FOLK Users.interest_list)."),
    child("FOLK User Skill", "skill", "FOLK Skill"),
    child("FOLK User Interest", "interest", "FOLK Interest"),
]

print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")
for d in DOCTYPES:
    s, _ = call("GET", "/api/resource/DocType/" + d["name"].replace(" ", "%20"))
    if s == 200:
        print("=", d["name"], "already exists"); continue
    print("+", d["name"])
    if COMMIT:
        s, r = call("POST", "/api/resource/DocType", d)
        if s != 200: raise SystemExit(f"! FAILED {s} {d['name']} {r}")

# New fields on FOLK Users, placed right after the old text field they replace.
ADD = [
    ("profession", {"fieldname": "college", "label": "College / Company", "fieldtype": "Link", "options": "FOLK College", "search_index": 1}),
    ("college", {"fieldname": "branch", "label": "Branch", "fieldtype": "Link", "options": "FOLK Branch"}),
    ("skills", {"fieldname": "skill_list", "label": "Skills", "fieldtype": "Table MultiSelect", "options": "FOLK User Skill"}),
    ("interests", {"fieldname": "interest_list", "label": "Interests", "fieldtype": "Table MultiSelect", "options": "FOLK User Interest"}),
]
s, r = call("GET", "/api/resource/DocType/FOLK%20Users")
if s != 200: raise SystemExit(f"! read FOLK Users {s} {r}")
doc = r["data"]; fields = doc["fields"]
changed = False
for after, f in ADD:
    if any(x["fieldname"] == f["fieldname"] for x in fields):
        print("= FOLK Users." + f["fieldname"], "already exists"); continue
    idx = next(i for i, x in enumerate(fields) if x["fieldname"] == after)
    fields.insert(idx + 1, f); changed = True
    print("+ FOLK Users." + f["fieldname"])
if changed and COMMIT:
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", doc)
    print("saved FOLK Users" if s == 200 else f"! {s} {r}")
if not COMMIT: print("\nDry run only. Re-run with --commit to write.")
