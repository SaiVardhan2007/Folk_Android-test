"""Area of stay as a list stored by ID (FOLK Area), moved over from the old typed area (FOLK Users.venue). Re-runnable.

  python3 -I scripts/phase26_area.py             dry run: writes NOTHING (prints the merge)
  python3 -I scripts/phase26_area.py --commit    adds FOLK Area + FOLK Users.area, moves the values over

Merging is done by scripts/area_aliases.py (checked by hand). The typed text in FOLK Users.venue is left as it was (hidden).
"With Parents" / "In Hostel" typed into the area box are really the Staying answer: they fill Staying when it is empty and are not areas.
A person whose area is already set is never changed. Everyone's venue / area / Staying is saved to ~/crm-export/backups/ first.
"""
import datetime, json, os, sys, urllib.parse, urllib.request, urllib.error
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from area_aliases import canon  # noqa: E402

COMMIT = "--commit" in sys.argv
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json",
     "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote
key = lambda s: "".join(ch for ch in s.lower() if ch.isalnum())


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

s, _ = call("GET", "/api/resource/DocType/FOLK%20Area")
if s == 200: print("= FOLK Area already exists")
else:
    print("+ DocType FOLK Area")
    if COMMIT:
        ok(*call("POST", "/api/resource/DocType", {
            "doctype": "DocType", "name": "FOLK Area", "module": "Custom", "custom": 1, "description": "Area where a person stays (FOLK Users.area).",
            "autoname": "hash", "naming_rule": "Random", "title_field": "title", "show_title_field_in_link": 1, "search_fields": "title",
            "sort_field": "title", "sort_order": "ASC", "track_changes": 1, "quick_entry": 1,
            "permissions": [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}],
            "fields": [{"fieldname": "title", "label": "Title", "fieldtype": "Data", "reqd": 1, "unique": 1, "in_list_view": 1, "in_standard_filter": 1}],
        }), "create FOLK Area")

doc = ok(*call("GET", "/api/resource/DocType/FOLK%20Users"), "read FOLK Users")["data"]
fields = doc["fields"]
names = {f["fieldname"] for f in fields}
if "area" in names: print("= FOLK Users.area already exists")
else:
    fields.insert(next(i for i, x in enumerate(fields) if x["fieldname"] == "venue") + 1,
                  {"fieldname": "area", "label": "Area of Stay", "fieldtype": "Link", "options": "FOLK Area", "in_standard_filter": 1, "search_index": 1})
    print("+ FOLK Users.area")
for f in fields:
    if f["fieldname"] == "venue" and not f.get("hidden"):
        f.update(hidden=1, read_only=1, label="Old area (text)"); print("  hide venue")
if COMMIT: ok(*call("PUT", "/api/resource/DocType/FOLK%20Users", doc), "save FOLK Users"); print("saved FOLK Users")

has_area = "area" in names or COMMIT
people = ok(*call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "venue", "current_stay"] + (["area"] if has_area else []))) + "&limit_page_length=0"), "list people")["data"]
plan = []  # (person, area, stay to fill)
for p in people:
    if p.get("area") or not (p.get("venue") or "").strip(): continue
    area, stay = canon(p["venue"])
    plan.append((p, area, stay if stay and not p.get("current_stay") else ""))
# One spelling per value: the first (most common) casing wins ("Kphb" -> "KPHB" when that is more common).
cnt = Counter(a for _, a, _ in plan if a)
best = {}
for a, _ in cnt.most_common(): best.setdefault(key(a), a)
plan = [(p, best[key(a)] if a else "", st) for p, a, st in plan]
titles = Counter(a for _, a, _ in plan if a)
print(f"{len(people)} people; {len(plan)} have a typed area -> {len(titles)} areas; {sum(1 for _, a, _ in plan if not a)} not an area; "
      f"{sum(1 for _, _, st in plan if st)} get Staying filled")
if not COMMIT:
    for t, n in titles.most_common(): print(f"  {n:4}  {t}")
    unmapped = Counter((p["venue"] or "").strip() for p, a, st in plan if not a and not st)
    print("\nTyped text that is not an area (left empty):", dict(unmapped))
    print("\nDry run only. Re-run with --commit to write.")
    raise SystemExit(0)

path = os.path.expanduser(f"~/crm-export/backups/folk_users_pre_area_list_{datetime.date.today()}.json")
os.makedirs(os.path.dirname(path), exist_ok=True)
json.dump(people, open(path, "w"), indent=1)
print("backup:", path)

have = {r["title"]: r["name"] for r in ok(*call("GET", "/api/resource/FOLK%20Area?fields=" + q(json.dumps(["name", "title"])) + "&limit_page_length=0"), "list areas")["data"]}
byKey = {key(t): i for t, i in have.items()}
for t in [*titles, "Others"]:
    if key(t) not in byKey:
        byKey[key(t)] = ok(*call("POST", "/api/resource/FOLK%20Area", {"title": t}), "add " + t)["data"]["name"]
print(f"{len(byKey)} areas in the list")
docs = []
for p, a, st in plan:
    upd = {"doctype": "FOLK Users", "docname": p["name"]}
    if a: upd["area"] = byKey[key(a)]
    if st: upd["current_stay"] = st
    if len(upd) > 2: docs.append(upd)
failed = []
for i in range(0, len(docs), 100):
    part = docs[i:i + 100]
    s, r = call("POST", "/api/method/frappe.client.bulk_update", {"docs": json.dumps(part)})
    bad = (r.get("message") or {}).get("failed_docs") if s == 200 else part
    if bad: failed += bad
    print(f"  {i + 1}-{i + len(part)}:", "ok" if s == 200 and not bad else f"! {s} {len(bad)} failed")
if failed: print("FAILED:", json.dumps(failed)[:2000])
print("Done.")
