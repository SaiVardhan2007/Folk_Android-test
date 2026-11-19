"""Adds the "Not Interested" role and moves the old CRM's "not interested" contacts onto it. Re-runnable.

  python3 -I scripts/phase17_not_interested_role.py             dry run: writes NOTHING
  python3 -I scripts/phase17_not_interested_role.py --commit    really writes

1. FOLK Users.user_tag gets the option "Not Interested" (contacts that must not be called; they can never sign in).
2. Every contact marked is_not_interested in the old CRM (~/crm-export/data/master_contacts.json) whose role here is
   still Public becomes "Not Interested". Coordinators and Admins are never changed (listed instead).
3. Calls still waiting ("Not Done") for those contacts are removed from coordinators' lists. Call history is kept.

Deploy the backend BEFORE running with --commit: older backends let every non-Public role sign in.
The old not_interested checkbox is left in ERPNext untouched but is no longer read by the app; the role is the only source of truth.
"""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote
ROLE = "Not Interested"


def call(method, path, body=None, tries=4):
    for attempt in range(tries):
        req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code in (429, 502, 503, 504) and attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return e.code, {"error": e.read().decode()[:800]}
        except Exception as e:
            if attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return 0, {"error": str(e)}


def phone(raw):
    d = "".join(ch for ch in str(raw or "") if ch.isdigit())
    if len(d) == 12 and d.startswith("91"): d = d[2:]
    if len(d) == 11 and d.startswith("0"): d = d[1:]
    return d if len(d) == 10 and d[0] in "6789" else None


def ok(s, r, what):
    if s != 200: raise SystemExit(f"! {what} failed {s} {r}")
    return r


print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")

# 1. role option
doc = ok(*call("GET", "/api/resource/DocType/FOLK%20Users"), "read DocType")["data"]
tag = next(f for f in doc["fields"] if f["fieldname"] == "user_tag")
opts = [o.strip() for o in (tag.get("options") or "").split("\n") if o.strip()]
if ROLE in opts:
    print(f"= role option already there: {opts}")
else:
    opts.insert(opts.index("Public") + 1 if "Public" in opts else len(opts), ROLE)
    print(f"+ role options -> {opts}")
    if COMMIT:
        tag["options"] = "\n".join(opts)
        ok(*call("PUT", "/api/resource/DocType/FOLK%20Users", doc), "save DocType")

# 2. who becomes Not Interested
masters = json.load(open(os.path.expanduser("~/crm-export/data/master_contacts.json")))
flagged = sorted({p for m in masters if m.get("is_not_interested") for p in [phone(m.get("phone"))] if p})
rows = ok(*call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "mob_no", "full_name", "user_tag"])) + "&filters=" + q(json.dumps([["mob_no", "in", flagged]])) + "&limit_page_length=0"), "find people")["data"]
by_mob = {r["mob_no"]: r for r in rows}
change = [r for r in rows if (r["user_tag"] or "Public") == "Public"]
already = [r for r in rows if r["user_tag"] == ROLE]
staff = [r for r in rows if r["user_tag"] not in ("Public", ROLE, None, "")]
missing = [p for p in flagged if p not in by_mob]
print(f"old CRM 'not interested': {len(flagged)} | to change Public -> {ROLE}: {len(change)} | already {ROLE}: {len(already)} | not found here: {len(missing)}")
for r in staff: print(f"  left alone (staff): {r['full_name']} {r['mob_no']} [{r['user_tag']}]")
for p in missing: print(f"  not in FOLK Users: {p}")

# 3. their open calls
targets = [r["name"] for r in change + already]
open_asg = ok(*call("GET", "/api/resource/FOLK%20Assignment?fields=" + q(json.dumps(["name", "person_name", "coordinator_name", "event_code"])) + "&filters=" + q(json.dumps([["person", "in", targets or ["-"]], ["status", "=", "Not Done"]])) + "&limit_page_length=0"), "find open calls")["data"]
print(f"open calls to remove: {len(open_asg)}")
for a in open_asg: print(f"  {a['person_name']} (assigned to {a['coordinator_name']}, {a['event_code']})")

if not COMMIT:
    print("\nDry run only. Re-run with --commit to write."); sys.exit(0)

for i in range(0, len(change), 200):
    part = change[i:i + 200]
    docs = [{"doctype": "FOLK Users", "docname": r["name"], "user_tag": ROLE} for r in part]
    s, r = call("POST", "/api/method/frappe.client.bulk_update", {"docs": json.dumps(docs)})
    failed = (r.get("message") or {}).get("failed_docs") if s == 200 else None
    print(f"  roles {i + 1}-{i + len(part)}:", "ok" if s == 200 and not failed else f"! {s} {failed or r}")
for i in range(0, len(open_asg), 100):
    names = [a["name"] for a in open_asg[i:i + 100]]
    s, r = call("POST", "/api/method/frappe.desk.reportview.delete_items", {"items": json.dumps(names), "doctype": "FOLK Assignment"})
    print(f"  removed {len(names)} open calls:", "ok" if s == 200 else f"! {s} {r}")
print("Done.")
