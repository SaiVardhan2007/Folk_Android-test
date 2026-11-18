"""Every event gets two public forms: Registration and Feedback.
  1. FOLK Feedback DocType (one row per person per event, ID = fb_key = "<event>-<person>")
  2. FOLK Form Link.link_type gains "Feedback"
  3. For every real event (not a contact list) that has no Registration / Feedback link yet, create one.
Existing links are never changed. Re-runnable. Dry run by default; add --commit to write.
Run: python3 -I scripts/phase14_event_forms.py [--commit]"""
import json, os, re, sys, urllib.parse, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
env = {}
for line in open(os.path.join(HERE, "..", ".dev.vars")):
    if "=" in line:
        k, v = line.strip().split("=", 1)
        env[k] = v
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote


def call(m, p, b=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + p, method=m, headers=H, data=json.dumps(b).encode() if b is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, {"error": e.read().decode()[:600]}


def slug_for(code, kind):
    """Same rule as the Worker's eventSlug(): readable and stable, e.g. rathayatra-2026-feedback."""
    base = re.sub(r"[^a-z0-9]+", "-", code.lower())[:24].strip("-") or "event"
    return f"{base}-{kind}"


PERM = [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}]
FEEDBACK = {
    "doctype": "DocType", "name": "FOLK Feedback", "module": "Custom", "custom": 1,
    "autoname": "field:fb_key", "sort_field": "creation", "sort_order": "DESC", "track_changes": 0, "quick_entry": 0, "permissions": PERM,
    "fields": [
        {"fieldname": "fb_key", "label": "Key", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1},
        {"fieldname": "event_code", "label": "Event", "fieldtype": "Link", "options": "FOLK Event", "reqd": 1, "in_list_view": 1, "search_index": 1},
        {"fieldname": "person", "label": "Person", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "search_index": 1},
        {"fieldname": "person_name", "label": "Name", "fieldtype": "Data", "fetch_from": "person.full_name", "read_only": 1, "in_list_view": 1},
        {"fieldname": "person_mob", "label": "Mobile", "fieldtype": "Data", "fetch_from": "person.mob_no", "read_only": 1, "search_index": 1},
        {"fieldname": "rating", "label": "Rating (1 to 5)", "fieldtype": "Int", "in_list_view": 1},
        {"fieldname": "liked", "label": "What they liked", "fieldtype": "Small Text"},
        {"fieldname": "improve", "label": "What can be better", "fieldtype": "Small Text"},
        {"fieldname": "comments", "label": "Other comments", "fieldtype": "Small Text"},
        {"fieldname": "via_link", "label": "Submitted through link", "fieldtype": "Data", "search_index": 1},
        {"fieldname": "submitted_at", "label": "Submitted at", "fieldtype": "Datetime"},
    ],
}

s, _ = call("GET", "/api/resource/DocType/FOLK%20Feedback")
if s == 200: print("= FOLK Feedback already exists")
else:
    print("+ FOLK Feedback DocType")
    if COMMIT:
        s, r = call("POST", "/api/resource/DocType", FEEDBACK)
        if s != 200: raise SystemExit(f"! FAILED {s} {r}")

s, r = call("GET", "/api/resource/DocType/FOLK%20Form%20Link")
doc = r["data"]
lt = next(f for f in doc["fields"] if f["fieldname"] == "link_type")
opts = lt["options"].split("\n")
if "Feedback" in opts: print("= link type Feedback already exists")
else:
    print("+ link type Feedback")
    if COMMIT:
        lt["options"] = "\n".join(opts + ["Feedback"])
        s, r = call("PUT", "/api/resource/DocType/FOLK%20Form%20Link", doc)
        if s != 200: raise SystemExit(f"! FAILED {s} {r}")

# Events (without is_list the field may not exist on very old setups: treat as real events)
s, r = call("GET", "/api/resource/FOLK%20Event?fields=" + q(json.dumps(["name", "event_name", "is_list"])) + "&limit_page_length=0")
events = [e for e in r["data"] if not e.get("is_list")]
s, r = call("GET", "/api/resource/FOLK%20Form%20Link?fields=" + q(json.dumps(["name", "event_code", "link_type"])) + "&limit_page_length=0")
links = r["data"]
for e in events:
    for kind, ltype, label in (("register", "Registration", "Registration"), ("feedback", "Feedback", "Feedback")):
        if any(l["event_code"] == e["name"] and l["link_type"] == ltype for l in links):
            print(f"= {e['name']}: {label} link exists"); continue
        doc = {"doctype": "FOLK Form Link", "slug": slug_for(e["name"], kind), "title": f"{e['event_name']} - {label}", "link_type": ltype, "event_code": e["name"], "is_open": 1}
        print(f"+ {e['name']}: {label} link /f/{doc['slug']}")
        if COMMIT:
            s, r = call("POST", "/api/resource/FOLK%20Form%20Link", doc)
            if s != 200: print("  ! FAILED", s, r)
if not COMMIT: print("Dry run. Nothing written. Add --commit to apply.")
