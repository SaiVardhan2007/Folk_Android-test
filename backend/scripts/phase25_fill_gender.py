"""Fills ONLY empty gender fields (M or F) from the person's name. Re-runnable; people who already have a gender are never touched.

  python3 -I scripts/phase25_fill_gender.py            dry run: writes NOTHING
  python3 -I scripts/phase25_fill_gender.py --commit   really writes

Names are judged for India / Hyderabad. A name that cannot be judged gets M (the rule the admin chose); those are marked "guess" in the output.
Before writing, the list (id, mobile, name, old value) is saved to ~/crm-export/backups/.
"""
import datetime, json, os, sys, urllib.parse, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote

FEMALE = {"lakshmi", "laxmi", "sravani", "swathi", "swati", "priya", "divya", "anitha", "anita", "sunitha", "sunita", "padma", "radha", "radhika", "rani", "devi", "kavya", "kavitha", "sirisha", "madhavi", "vasavi", "bhavani", "bhargavi", "pooja", "puja", "sneha", "shruthi", "sruthi", "meena", "meenakshi", "sita", "seetha", "gayatri", "gayathri", "sandhya", "sowmya", "soumya", "harini", "keerthi", "keerthana", "mounika", "manasa", "navya", "nikhitha", "nikita", "pavani", "prathyusha", "ramya", "rekha", "renuka", "sai", "sarika", "shilpa", "spandana", "tejaswini", "uma", "varsha", "vaishnavi", "yamini", "durga", "jyothi", "jyoti", "latha", "lata", "mamatha", "mahalakshmi", "bindu", "deepika", "deepthi", "sushma", "sujatha"}
FEMALE.discard("sai")  # Sai is used for both: not judged as female
MALE = {"naveen", "banish", "bhawin", "bhavin", "jayadeva", "ravi", "kiran", "suresh", "ramesh", "mahesh", "venkat", "krishna", "srinivas", "raju", "anil", "sunil", "vijay", "rahul", "arjun", "manish", "mohan", "sandeep", "prasad", "teja", "charan", "dasa", "das", "dasa", "prabhu"}


def judge(full):
    words = [w.strip(".,").lower() for w in full.split()]
    if any(w in FEMALE for w in words): return "F", "name"
    if any(w in MALE for w in words): return "M", "name"
    return "M", "guess"


def call(method, path, body=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:600]}


print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")
s, r = call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "mob_no", "full_name", "gender", "user_tag"])) + "&filters=" + q(json.dumps([["gender", "in", ["", None]]])) + "&limit_page_length=0")
if s != 200: raise SystemExit(f"! {s} {r}")
rows = r["data"]
plan = [(x, *judge(x["full_name"] or "")) for x in rows]
for x, g, how in plan: print(f"  {g}  {how:5}  {x['mob_no']}  {x['full_name']}  [{x['user_tag']}]")
if COMMIT:
    d = os.path.expanduser("~/crm-export/backups"); os.makedirs(d, exist_ok=True)
    f = os.path.join(d, f"gender-before-{datetime.datetime.now():%Y%m%d-%H%M%S}.json")
    json.dump(rows, open(f, "w"), ensure_ascii=False, indent=1); print("backup:", f)
    for x, g, _ in plan:
        # Re-check right before writing: a gender someone filled in meanwhile is never overwritten.
        s, cur = call("GET", "/api/resource/FOLK%20Users/" + q(x["name"]))
        if s == 200 and not cur["data"].get("gender"):
            s, rr = call("PUT", "/api/resource/FOLK%20Users/" + q(x["name"]), {"gender": g})
            if s != 200: print("! failed", x["mob_no"], s, rr)
    print("done")
else:
    print("dry run finished: re-run with --commit")
