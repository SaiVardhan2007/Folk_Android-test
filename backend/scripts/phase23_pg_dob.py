"""PG / Hostel as a list stored by ID, Date of birth instead of a typed age, and removal of the Map link and Call number fields.

  python3 -I scripts/phase23_pg_dob.py                    dry run: writes NOTHING (prints the PG merge)
  python3 -I scripts/phase23_pg_dob.py --commit           adds FOLK PG + FOLK Users.pg / .dob, moves PG names over, hides the old fields
  python3 -I scripts/phase23_pg_dob.py --drop-removed     deletes FOLK Users.gmap_link and .call_no (both empty).
                                                          Run it only AFTER the new backend is deployed (the old one still reads them).

PG names are merged by scripts/pg_aliases.py (checked by hand). A person whose new PG field is already set is never changed (safe to re-run).
The old typed age stays in ERPNext (hidden) and is shown until a date of birth is entered. Nobody has a date of birth yet: the old system never asked.
Before writing, everyone's current pg_name is saved to ~/crm-export/backups/.
"""
import datetime, json, os, sys, urllib.parse, urllib.request, urllib.error
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from pg_aliases import canon  # noqa: E402

COMMIT = "--commit" in sys.argv
DROP = "--drop-removed" in sys.argv
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


def users_doc():
    return ok(*call("GET", "/api/resource/DocType/FOLK%20Users"), "read FOLK Users")["data"]


if DROP:
    doc = users_doc()
    gone = [f["fieldname"] for f in doc["fields"] if f["fieldname"] in ("gmap_link", "call_no")]
    people = ok(*call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "gmap_link", "call_no"])) + "&limit_page_length=0"), "list")["data"] if gone else []
    filled = [p for p in people if (p.get("gmap_link") or "").strip() or (p.get("call_no") or "").strip()]
    if filled: raise SystemExit(f"! {len(filled)} people have a map link or call number; not deleting. {filled[:5]}")
    doc["fields"] = [f for f in doc["fields"] if f["fieldname"] not in ("gmap_link", "call_no")]
    if gone: ok(*call("PUT", "/api/resource/DocType/FOLK%20Users", doc), "delete fields")
    print("deleted:", gone or "nothing (already gone)")
    raise SystemExit(0)

print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")

# 1. The FOLK PG list.
s, _ = call("GET", "/api/resource/DocType/FOLK%20PG")
if s == 200: print("= FOLK PG already exists")
else:
    print("+ DocType FOLK PG")
    if COMMIT:
        ok(*call("POST", "/api/resource/DocType", {
            "doctype": "DocType", "name": "FOLK PG", "module": "Custom", "custom": 1, "description": "PG / hostel names (FOLK Users.pg).",
            "autoname": "hash", "naming_rule": "Random", "title_field": "title", "show_title_field_in_link": 1, "search_fields": "title",
            "sort_field": "title", "sort_order": "ASC", "track_changes": 1, "quick_entry": 1,
            "permissions": [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}],
            "fields": [{"fieldname": "title", "label": "Title", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1, "in_standard_filter": 1}],
        }), "create FOLK PG")

# 2. New fields on FOLK Users; the old ones are hidden (values kept).
doc = users_doc()
fields = doc["fields"]
names = {f["fieldname"] for f in fields}
for after, f in [("pg_name", {"fieldname": "pg", "label": "PG / Residence", "fieldtype": "Link", "options": "FOLK PG", "in_standard_filter": 1}),
                 ("age", {"fieldname": "dob", "label": "Date of Birth", "fieldtype": "Date"})]:
    if f["fieldname"] in names: print("= FOLK Users." + f["fieldname"], "already exists"); continue
    fields.insert(next(i for i, x in enumerate(fields) if x["fieldname"] == after) + 1, f)
    print("+ FOLK Users." + f["fieldname"])
for f in fields:
    if f["fieldname"] == "pg_name" and not f.get("hidden"):
        f.update(hidden=1, read_only=1, label="Old PG (text)"); print("  hide pg_name")
    if f["fieldname"] == "age" and not f.get("hidden"):
        f.update(hidden=1, read_only=1, label="Old age (as typed)"); print("  hide age (still shown until a date of birth is entered)")
if COMMIT: ok(*call("PUT", "/api/resource/DocType/FOLK%20Users", doc), "save FOLK Users"); print("saved FOLK Users")

# 3. PG names -> list values.
has_pg = "pg" in names or COMMIT
people = ok(*call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "pg_name"] + (["pg"] if has_pg else []))) + "&limit_page_length=0"), "list people")["data"]
plan = [(p, canon(p.get("pg_name"))) for p in people if (p.get("pg_name") or "").strip() and not p.get("pg")]
titles = Counter(t for _, t in plan if t)
print(f"{len(people)} people; {len(plan)} have a PG name -> {len(titles)} values; {sum(1 for _, t in plan if not t)} emptied (not a PG)")
if not COMMIT:
    for t, n in titles.most_common(): print(f"  {n:4}  {t}")
    print("\nDry run only. Re-run with --commit to write.")
    raise SystemExit(0)

path = os.path.expanduser(f"~/crm-export/backups/folk_users_pre_pg_list_{datetime.date.today()}.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(people, open(path, "w"), indent=1)
print("backup:", path)

have = {r["title"]: r["name"] for r in ok(*call("GET", "/api/resource/FOLK%20PG?fields=" + q(json.dumps(["name", "title"])) + "&limit_page_length=0"), "list PG")["data"]}
for t in titles:
    if t not in have:
        have[t] = ok(*call("POST", "/api/resource/FOLK%20PG", {"title": t}), "add " + t)["data"]["name"]
print(f"{len(have)} PG values in the list")
docs = [{"doctype": "FOLK Users", "docname": p["name"], "pg": have[t]} for p, t in plan if t]
failed = []
for i in range(0, len(docs), 100):
    part = docs[i:i + 100]
    s, r = call("POST", "/api/method/frappe.client.bulk_update", {"docs": json.dumps(part)})
    bad = (r.get("message") or {}).get("failed_docs") if s == 200 else part
    if bad: failed += bad
    print(f"  {i + 1}-{i + len(part)}:", "ok" if s == 200 and not bad else f"! {s} {len(bad)} failed")
if failed: print("FAILED:", json.dumps(failed)[:2000])
print("Done.")
