"""Public registration links: FOLK Form Link + attribution fields on FOLK Registration. Re-runnable."""
import json, os, urllib.parse, urllib.request, urllib.error
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
def call(m, p, b=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + p, method=m, headers=H, data=json.dumps(b).encode() if b is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, {"error": e.read().decode()[:800]}
PERM = [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}]
LINK = {
    "doctype": "DocType", "name": "FOLK Form Link", "module": "Custom", "custom": 1,
    "autoname": "field:slug", "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0, "permissions": PERM,
    "fields": [
        {"fieldname": "slug", "label": "Link code", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1},
        {"fieldname": "title", "label": "Title", "fieldtype": "Data", "reqd": 1, "in_list_view": 1},
        {"fieldname": "link_type", "label": "Type", "fieldtype": "Select", "options": "Registration\nVolunteer", "reqd": 1, "in_list_view": 1},
        {"fieldname": "event_code", "label": "Event", "fieldtype": "Link", "options": "FOLK Event", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "assigned_to", "label": "Assigned to", "fieldtype": "Link", "options": "FOLK Users", "search_index": 1},
        {"fieldname": "assigned_name", "label": "Assigned to (name)", "fieldtype": "Data", "fetch_from": "assigned_to.full_name", "read_only": 1},
        {"fieldname": "is_open", "label": "Open", "fieldtype": "Check", "default": "1"},
        {"fieldname": "intro", "label": "Message on the page", "fieldtype": "Small Text"},
        {"fieldname": "ask_dinner", "label": "Ask about dinner", "fieldtype": "Check", "default": "0"},
        {"fieldname": "ask_transport", "label": "Ask about transport", "fieldtype": "Check", "default": "0"},
        {"fieldname": "ask_donation", "label": "Ask about donation", "fieldtype": "Check", "default": "0"},
        {"fieldname": "slot_options", "label": "Volunteer time slots (one per line)", "fieldtype": "Small Text"},
        {"fieldname": "service_options", "label": "Volunteer services (one per line)", "fieldtype": "Small Text"},
    ],
}
s, _ = call("GET", "/api/resource/DocType/FOLK%20Form%20Link")
if s == 200: print("= FOLK Form Link already exists")
else:
    s, r = call("POST", "/api/resource/DocType", LINK); print(("+ created FOLK Form Link" if s == 200 else f"! FAILED {s} {r}"))
s, r = call("GET", "/api/resource/DocType/FOLK%20Registration")
doc = r["data"]; fields = doc["fields"]; have = {f["fieldname"] for f in fields}; changed = False
for f in [{"fieldname": "via_link", "label": "Registered through link", "fieldtype": "Data", "search_index": 1},
          {"fieldname": "referred_by", "label": "Link owner", "fieldtype": "Link", "options": "FOLK Users", "search_index": 1}]:
    if f["fieldname"] not in have: fields.append(f); changed = True; print("+ FOLK Registration." + f["fieldname"])
if changed:
    s, r = call("PUT", "/api/resource/DocType/FOLK%20Registration", doc); print("saved" if s == 200 else f"! {s} {r}")
