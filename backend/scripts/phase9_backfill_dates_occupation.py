"""One-off fix after the CRM import: (1) registered_on = the person's OLD registration date; (2) undo guessed occupations. Re-runnable."""
import json, os, urllib.parse, urllib.request, urllib.error
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-fix/1.0"}
q = urllib.parse.quote
def call(m, p, b=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + p, method=m, headers=H, data=json.dumps(b).encode() if b is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=120) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, {"error": e.read().decode()[:300]}
def phone(raw):
    d = "".join(c for c in str(raw or "") if c.isdigit())
    if len(d) == 12 and d.startswith("91"): d = d[2:]
    return d if len(d) == 10 else None
def ist_date(ts): return (datetime.strptime(ts[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S") + timedelta(hours=5, minutes=30)).strftime("%Y-%m-%d")

old = {phone(m["phone"]): ist_date(m["created_at"]) for m in json.load(open(os.path.expanduser("~/crm-export/data/master_contacts.json")))}
STD = {"student", "working", "business", "others", "job search", ""}
typed = {}
for r in json.load(open(os.path.expanduser("~/crm-export/data/registrations.json"))):
    v = " ".join((r.get("occupation") or "").split())
    if v.lower() not in STD: typed[phone(r["phone"])] = v

s, r = call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "mob_no", "creation", "registered_on", "occupation", "comments"])) + "&limit_page_length=0")
people = r["data"]
def fix(p):
    patch = {}
    if not p.get("registered_on"): patch["registered_on"] = old.get(p["mob_no"]) or p["creation"][:10]
    if p["mob_no"] in typed and p.get("occupation"):
        patch["occupation"] = ""
        note = f"Occupation as typed: {typed[p['mob_no']]}"
        if note not in (p.get("comments") or ""): patch["comments"] = ((p.get("comments") or "") + " | " if p.get("comments") else "") + note
    if not patch: return True
    s, r = call("PUT", "/api/resource/FOLK%20Users/" + q(p["name"]), patch)
    if s != 200: print("!", p["name"], s, r)
    return s == 200
with ThreadPoolExecutor(6) as ex: res = list(ex.map(fix, people))
print(f"{sum(res)} ok, {len(res) - sum(res)} failed, of {len(people)}; typed occupations handled: {sorted(typed.values())}")
