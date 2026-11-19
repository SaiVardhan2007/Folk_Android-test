"""Adds the old CRM operators (callers) as Coordinators in FOLK Users and links their earlier calls to them. Re-runnable.

  python3 -I scripts/phase16_import_operators.py             dry run: writes NOTHING
  python3 -I scripts/phase16_import_operators.py --commit    really writes

Per operator (contact_operators.json):
  - no mobile number in the old CRM            -> skipped (listed; add them by hand once their number is known)
  - number not in FOLK Users                   -> created as Coordinator (they sign in with their number + an SMS code),
                                                  active only if they were active in the old CRM, call_limit = old capacity
  - number is a Public contact                 -> becomes a Coordinator (same as a self sign-up), call_limit set
  - number is already Coordinator / Admin      -> left exactly as it is
Then every FOLK Call Log row whose legacy_caller is "<name> (<number>)" and has no coordinator gets that coordinator
(legacy_caller text is kept)."""
import json, os, sys, time, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-import/1.0", "Accept": "application/json"}
q = urllib.parse.quote


def call(method, path, body=None, tries=4):
    for attempt in range(tries):
        req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code in (429, 502, 503, 504) and attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return e.code, {"error": e.read().decode()[:600]}
        except Exception as e:
            if attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return 0, {"error": str(e)}


def phone(raw):
    d = "".join(ch for ch in str(raw or "") if ch.isdigit())
    if len(d) == 12 and d.startswith("91"): d = d[2:]
    if len(d) == 11 and d.startswith("0"): d = d[1:]
    return d if len(d) == 10 and d[0] in "6789" else None


def ist_date(ts):
    return (datetime.strptime(ts[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S") + timedelta(hours=5, minutes=30)).strftime("%Y-%m-%d") if ts else None


ops = json.load(open(os.path.expanduser("~/crm-export/data/contact_operators.json")))
with_phone = [(o, phone(o.get("phone"))) for o in ops]
skipped = [o for o, p in with_phone if not p]
todo = [(o, p) for o, p in with_phone if p]

s, r = call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "mob_no", "full_name", "user_tag", "is_active", "call_limit"])) + "&filters=" + q(json.dumps([["mob_no", "in", [p for _, p in todo]]])) + "&limit_page_length=0")
if s != 200: raise SystemExit(f"! lookup failed {s} {r}")
existing = {x["mob_no"]: x for x in r["data"]}

coord_id = {}  # number -> FOLK Users ID, for linking calls
created = promoted = kept = 0
for o, p in todo:
    cap = int(o.get("capacity") or 0) or None
    active = 1 if o.get("is_active") else 0
    ex = existing.get(p)
    if ex is None:
        print(f"+ create   {p}  {o['name']}  (limit {cap}, {'active' if active else 'disabled'})")
        created += 1
        if COMMIT:
            s, r = call("POST", "/api/resource/FOLK%20Users", {"mob_no": p, "full_name": o["name"].strip(), "user_tag": "Coordinator", "is_active": active, "call_limit": cap,
                                                              "registered_by": "old CRM operator", "registered_on": ist_date(o.get("created_at"))})
            if s != 200: print(f"  ! FAILED {s} {r}"); continue
            coord_id[p] = r["data"]["name"]
    elif (ex.get("user_tag") or "Public") == "Public":
        print(f"~ promote  {p}  {ex['full_name']} ({ex['name']}) Public -> Coordinator  (limit {cap}, {'active' if active else 'disabled'})")
        promoted += 1
        coord_id[p] = ex["name"]
        if COMMIT:
            s, r = call("PUT", f"/api/resource/FOLK%20Users/{q(ex['name'])}", {"user_tag": "Coordinator", "is_active": active, "call_limit": cap})
            if s != 200: print(f"  ! FAILED {s} {r}"); coord_id.pop(p)
    else:
        print(f"= keep     {p}  {ex['full_name']} ({ex['name']}) is already {ex['user_tag']}")
        kept += 1
        coord_id[p] = ex["name"]
for o in skipped:
    print(f"- skipped  {o['name']}: no mobile number in the old CRM")

# Link earlier calls. In a dry run, people still to be created have no ID yet, so just count.
s, r = call("GET", "/api/resource/FOLK%20Call%20Log?fields=" + q(json.dumps(["name", "legacy_caller"])) + "&filters=" + q(json.dumps([["legacy_caller", "!=", ""], ["coordinator", "is", "not set"]])) + "&limit_page_length=0")
if s != 200: raise SystemExit(f"! call log lookup failed {s} {r}")
rows = r["data"]
def number_of(txt):
    return phone(txt.rsplit("(", 1)[-1].rstrip(")")) if "(" in txt else None
by_num = {}
for x in rows: by_num.setdefault(number_of(x["legacy_caller"] or ""), []).append(x["name"])
print(f"\nCall log rows to link: {sum(len(v) for k, v in by_num.items() if k in {p for _, p in todo})} of {len(rows)} (rest have no number / not an operator with a number)")
for k, v in sorted(by_num.items(), key=lambda kv: -len(kv[1])): print(f"   {k or 'no number'}: {len(v)}")

if COMMIT:
    jobs = [(n, coord_id[k]) for k, v in by_num.items() if k in coord_id for n in v]
    def link(j):
        s, r = call("PUT", f"/api/resource/FOLK%20Call%20Log/{q(j[0])}", {"coordinator": j[1]})
        return s == 200
    with ThreadPoolExecutor(6) as ex_: ok = sum(ex_.map(link, jobs))
    print(f"linked {ok}/{len(jobs)} call logs")
print(f"\n{'COMMITTED' if COMMIT else 'DRY RUN (nothing written)'}: {created} new, {promoted} promoted, {kept} already staff, {len(skipped)} skipped")
