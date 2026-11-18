"""Adds FOLK Users.folk_guide (default "vkgd") and fills it for everyone who has none. Re-runnable.
Dry run by default: python3 phase12_folk_guide.py            (shows what would change)
                    python3 phase12_folk_guide.py --commit   (adds the field, then fills the people)"""
import json, os, sys, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor

COMMIT = "--commit" in sys.argv
VALUE = "vkgd"
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote


def call(m, p, b=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + p, method=m, headers=H, data=json.dumps(b).encode() if b is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, {"error": e.read().decode()[:500]}


s, d = call("GET", "/api/resource/DocType/FOLK%20Users")
doc = d["data"]
fields = doc["fields"]
if not any(f["fieldname"] == "folk_guide" for f in fields):
    after = next(i for i, f in enumerate(fields) if f["fieldname"] == "fg_mob_no")
    fields.insert(after + 1, {"fieldname": "folk_guide", "label": "Folk Guide", "fieldtype": "Data", "default": VALUE, "in_standard_filter": 1})
    print("+ field folk_guide (default %s)" % VALUE)
    if COMMIT:
        s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", doc)
        print("schema saved" if s == 200 else f"! {s} {r}")
        if s != 200: sys.exit(1)
else:
    print("field folk_guide already exists")

s, r = call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "folk_guide"])) + "&limit_page_length=0")
if s != 200:
    # Before the field exists (dry run) the query fails; every person would be filled.
    s, r = call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name"])) + "&limit_page_length=0")
people = [p for p in r["data"] if not (p.get("folk_guide") or "").strip()]
print(f"{len(people)} of {len(r['data'])} people have no Folk Guide")
if not COMMIT:
    print("Dry run. Nothing written. Add --commit to apply.")
    sys.exit(0)


def fill(p):
    s, r = call("PUT", "/api/resource/FOLK%20Users/" + q(p["name"]), {"folk_guide": VALUE})
    if s != 200: print("!", p["name"], s, r)
    return s == 200


with ThreadPoolExecutor(6) as ex: res = list(ex.map(fill, people))
print(f"{sum(res)} ok, {len(res) - sum(res)} failed")
