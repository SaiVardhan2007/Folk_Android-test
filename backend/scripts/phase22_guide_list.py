"""FOLK Guide as a list stored by ID, with the guide's phone number kept on the guide (not on each person). Re-runnable.

  python3 -I scripts/phase22_guide_list.py            dry run: writes NOTHING
  python3 -I scripts/phase22_guide_list.py --commit   really writes

  FOLK Guide  (random ID, Title in capitals e.g. "VKGD", Mobile, Default)  <- FOLK Users.guide (Link)
Every person with no guide yet gets the default guide (VKGD). Guides are added/edited only in ERPNext (the app has no Add button).
The old per-person text fields (folk_guide, fg_name, fg_mob_no, call_no) are hidden in ERPNext; their values are kept.
Before writing, everyone's old values of those fields are saved to ~/crm-export/backups/.
"""
import datetime, json, os, sys, urllib.parse, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
GUIDE, GUIDE_MOB = "VKGD", "9133318576"
OLD = ("folk_guide", "fg_name", "fg_mob_no", "call_no")
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json",
     "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote


def call(method, path, body=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:800]}


def ok(s, r, what):
    if s != 200: raise SystemExit(f"! {what}: {s} {r}")
    return r


print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")

# 1. The FOLK Guide list.
s, _ = call("GET", "/api/resource/DocType/FOLK%20Guide")
if s == 200:
    print("= FOLK Guide already exists")
else:
    print("+ DocType FOLK Guide")
    if COMMIT:
        ok(*call("POST", "/api/resource/DocType", {
            "doctype": "DocType", "name": "FOLK Guide", "module": "Custom", "custom": 1,
            "description": "FOLK guides (FOLK Users.guide). Title in capital letters; the mobile is printed and sent with the guide name.",
            "autoname": "hash", "naming_rule": "Random", "title_field": "title", "show_title_field_in_link": 1, "search_fields": "title,mobile",
            "sort_field": "title", "sort_order": "ASC", "track_changes": 1, "quick_entry": 1,
            "permissions": [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}],
            "fields": [
                {"fieldname": "title", "label": "Guide Name", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1, "description": "In capital letters, e.g. VKGD"},
                {"fieldname": "mobile", "label": "Mobile", "fieldtype": "Data", "reqd": 1, "length": 10, "in_list_view": 1},
                {"fieldname": "is_default", "label": "Default for new people", "fieldtype": "Check", "in_list_view": 1},
            ],
        }), "create FOLK Guide")

guide_id = None
if COMMIT or s == 200:
    rows = ok(*call("GET", "/api/resource/FOLK%20Guide?fields=" + q(json.dumps(["name", "title", "mobile", "is_default"])) + "&limit_page_length=0"), "list guides")["data"]
    hit = next((r for r in rows if r["title"].strip().upper() == GUIDE), None)
    if hit: guide_id = hit["name"]; print(f"= guide {GUIDE} ({hit['mobile']}) id {guide_id}")
    elif COMMIT:
        guide_id = ok(*call("POST", "/api/resource/FOLK%20Guide", {"title": GUIDE, "mobile": GUIDE_MOB, "is_default": 1}), "add guide")["data"]["name"]
        print(f"+ guide {GUIDE} {GUIDE_MOB} id {guide_id}")
if not guide_id: print(f"+ guide {GUIDE} {GUIDE_MOB} (default)")

# 2. FOLK Users.guide (Link), placed where the old guide fields are; the old ones are hidden (values kept).
doc = ok(*call("GET", "/api/resource/DocType/FOLK%20Users"), "read FOLK Users")["data"]
fields = doc["fields"]
has_field = any(f["fieldname"] == "guide" for f in fields)
if not has_field:
    idx = next(i for i, f in enumerate(fields) if f["fieldname"] == "fg_name")
    fields.insert(idx, {"fieldname": "guide", "label": "FOLK Guide", "fieldtype": "Link", "options": "FOLK Guide", "in_standard_filter": 1, "default": guide_id})
    print("+ FOLK Users.guide (new people get VKGD by default, however they are added)")
else:
    print("= FOLK Users.guide already exists")
    g = next(f for f in fields if f["fieldname"] == "guide")
    if guide_id and not g.get("default"): g["default"] = guide_id; print("  default ->", guide_id)
for f in fields:
    if f["fieldname"] in OLD and not f.get("hidden"):
        f["hidden"] = 1; f["read_only"] = 1
        if not f["label"].startswith("Old "): f["label"] = "Old " + f["label"]
        print("  hide", f["fieldname"])
if COMMIT:
    ok(*call("PUT", "/api/resource/DocType/FOLK%20Users", doc), "save FOLK Users")
    print("saved FOLK Users")

# 3. Everyone with no guide gets VKGD.
cols = ["name"] + list(OLD) + (["guide"] if has_field or COMMIT else [])
people = ok(*call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(cols)) + "&limit_page_length=0"), "list people")["data"]
todo = [p for p in people if not p.get("guide")]
print(f"{len(people)} people, {len(todo)} get guide {GUIDE}")
if COMMIT and todo:
    path = os.path.expanduser(f"~/crm-export/backups/folk_users_pre_guide_list_{datetime.date.today()}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(people, open(path, "w"), indent=1)
    print("backup:", path)
    failed = []
    for i in range(0, len(todo), 100):
        part = [{"doctype": "FOLK Users", "docname": p["name"], "guide": guide_id} for p in todo[i:i + 100]]
        s, r = call("POST", "/api/method/frappe.client.bulk_update", {"docs": json.dumps(part)})
        bad = (r.get("message") or {}).get("failed_docs") if s == 200 else part
        if bad: failed += bad
        print(f"  {i + 1}-{i + len(part)}:", "ok" if s == 200 and not bad else f"! {s} {len(bad)} failed")
    if failed: print("FAILED:", json.dumps(failed)[:2000])
if not COMMIT: print("\nDry run only. Re-run with --commit to write.")
