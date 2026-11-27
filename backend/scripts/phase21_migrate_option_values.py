"""Moves College / Company, Branch, Skills and Interests onto the ID-based lists (phase20), with spellings merged. Re-runnable.

  python3 -I scripts/phase21_migrate_option_values.py            dry run: writes NOTHING, prints every merge for review
  python3 -I scripts/phase21_migrate_option_values.py --commit   really writes

Where the values come from
  College / Company  FOLK Users.profession (filled from the old CRM's company_college / college_name / profession, plus later app edits).
                     The import appended the branch, e.g. "JBIT (CSE)": that part goes to Branch.
  Branch             that appended part, else the old CRM's feedback_contacts.branch for the same mobile number.
  Skills, Interests  FOLK Users.skills / interests (comma separated). Old CRM skill IDs (UUIDs) are turned into their names.

How spellings are merged
  1. Same letters and digits, ignoring case, spaces and punctuation, are the same value ("C.B.I.T" = "Cbit" = "CBIT").
  2. COLLEGE below lists every other spelling of the same place, checked by hand (abbreviations, full names, typos).
  3. JUNK is not a college or company ("College", "Student", "1-40" ...): left empty.
  Anything else is kept as typed (capitalisation tidied).

Before writing, the current values of everyone are saved to ~/crm-export/backups/. The old text fields are then hidden in ERPNext
(their values are kept, untouched) so only the new dropdown fields are edited from now on.
"""
import datetime, json, os, re, sys, time, urllib.parse, urllib.request, urllib.error
from collections import Counter, defaultdict

COMMIT = "--commit" in sys.argv
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
q = urllib.parse.quote
CRM = os.path.expanduser("~/crm-export")


def call(method, path, body=None, tries=4):
    for attempt in range(tries):
        req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return r.status, json.loads(r.read() or b"{}")
        except urllib.error.HTTPError as e:
            if e.code in (429, 502, 503, 504) and attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return e.code, {"error": e.read().decode()[:800]}
        except Exception as e:
            if attempt < tries - 1:
                time.sleep(2 * (attempt + 1)); continue
            return 0, {"error": str(e)}


def ok(s, r, what):
    if s != 200: raise SystemExit(f"! {what} failed {s} {r}")
    return r


def key(s):
    return re.sub(r"[^a-z0-9]", "", (s or "").lower())


def phone(raw):
    d = re.sub(r"\D", "", str(raw or ""))
    if len(d) == 12 and d.startswith("91"): d = d[2:]
    if len(d) == 11 and d.startswith("0"): d = d[1:]
    return d if len(d) == 10 else None


# ---------------------------------------------------------------- College / Company
# Final title -> every other spelling found in the data (matched ignoring case, spaces and punctuation).
COLLEGE = {
    "CBIT - Chaitanya Bharathi Institute of Technology": ["CBIT", "Cbit collage", "CBIT College", "CBIY", "Chaitanya Bharathi Institute of Technology"],
    "CDU - Chaitanya Deemed to be University": [
        "CDU", "Chaitanya deemed to be university", "Chaitanya Deemed to be University (CDU)", "Chaitanya deemed to university", "Chaitanya deemed University",
        "Chaitanya demeed to be university", "Chaitanya demeed to be universtity", "Chaitanya demeed university", "Chaitanya demmed to be university",
        "Chaitanya university", "Chaithanya deemed to be university", "Chatinya demed"],
    # NIAT students study at the CDU campus; entries naming both are NIAT (the institute they attend).
    "NIAT - NxtWave Institute of Advanced Technologies": [
        "NIAT", "NIAT CDU", "Niat(CDU)", "CDU*NIAT", "CDUXNIAT", "CDU(NXTWAVE)", "NxtWave (CDU)", "Chaitanya deemed to be university - NIAT",
        "NIAT × CHAITANYA DEEMED TO BE UNIVERSITY", "NIAT-chaithanya deemed to be university", "Niat x chaitanya deemed to be university", "NIAT X Chaitanya University",
        "Nextwave institute of advance and technology", "Next wave institute of advanced technologies", "Nextwave institute of advanced technology",
        "Nextwave institution of advance technology", "NXT WAVE INNOVATION OF ADVANCE TECHNOLOGY", "NXT WAVE INSTITUTE OF ADVANCED TECHNOLOGIES",
        "Nxt wave institute of advanced technology", "Nxtwave institute of advance technology", "NXT wave institution of advance technology"],
    # "JBIT" in the old CRM is JBIET: the same people registered as "JBIET" elsewhere.
    "JBIET - JB Institute of Engineering and Technology": ["JBIT", "JBIET", "Jbiet coll8", "JBIET college", "JB institute of Engineering and Technology", "J.B Institute of Engineering & Technology", "Jb institute of technology"],
    "JBREC - Joginpally B.R. Engineering College": ["Jbrec"],
    "JBR Architecture College": ["Jbr architecture college"],
    "MGIT - Mahatma Gandhi Institute of Technology": ["MGIT", "MGIT COLLEGE", "Mahatma Gandhi Institute of Technology", "Mahatma Gandhi Institute Of Technology, Gandipet, Hyderabad"],
    "VJIT - Vidya Jyothi Institute of Technology": ["VJIT", "Vidya Jyothi", "Vidya Jyothi Institute of", "Vidya Jyothi Institute of Technology", "Vidya Jyoti Institute College"],
    "VNR VJIET - VNR Vignana Jyothi Institute of Engineering and Technology": ["VNR VJIET"],
    # VASV is Vasavi's college code (Krishnashtami form).
    "Vasavi College of Engineering": ["VASV", "VASAVI", "Vasari college of engineering"],
    "KGRCET - KG Reddy College of Engineering and Technology": [
        "KGRCET", "KG Reddy", "Kg Reddy College", "KG Reddy college of engineering and technology", "Kgreddy college of engineering technology",
        "Kg reddy college og engineer", "Kg reddy engineering college"],
    "IFHE - ICFAI Foundation for Higher Education": ["ICFAI", "ICFAI University", "ICFAI University, Hyderabad", "Icfai foundation for higher education"],
    "IBS Hyderabad - ICFAI Business School": ["IBS", "ICFAI Business School,Donthanapally"],
    "St. Martin's Engineering College": ["St Martin's Engineering College", "St.Martins engineering college"],
    "GRIET - Gokaraju Rangaraju Institute of Engineering and Technology": ["Gokaraju Rangaraju"],
    "KL University Hyderabad (KLH)": ["KLH"],
    "KL University": ["Klu"],
    "Malla Reddy Institute of Technology": ["Mallareddy institute of technology"],
    "BITS Pilani, Hyderabad Campus": ["Bits pilani, Hyderabad campus"],
    "G. Pullaiah College of Engineering and Technology (GPCET), Kurnool": ["G.Pullaiah College of Engineering and Technology,kurnool Gpcet"],
    "VIT Vellore": ["Vit vellore"],
    "VBIT": ["Vbit"],
    "Akshara Degree College": ["Akshara degree College"],
    "Dr. Patnam Mahender Reddy Institute of Medical Sciences": ["Dr patnam Mahender reddy", "Dr.Patnam Mahender Reddy Institute of Medical Sciences"],
    "Liverpool John Moores University": ["Liverpool John Morris University"],
    "Sri Chaitanya Educational Institutions": ["Sri chaitanya", "Sri Chaitanya school"],
    "Cognizant": ["Cognizant", "Cognizant Company", "Cognizant gar", "Cognizant Technology", "Cognizant technology solutions", "CTS"],
    # A "CG" person registered as "Capegemini" elsewhere.
    "Capgemini": ["Capgemini", "Capgemini services LTD", "CG", "Capegemini"],
    "Conduent": ["Conduent", "Conduent business services"],
    "CorroHealth": ["Corrohealth", "Corroehealth", "Corro health care", "Corro Health Infotech private limited"],
    "IntouchCX": ["Intouch", "Intouchcx", "Intouchcx company"],
    "Jarvis Business Solutions": ["Jarvis Business solution"],
    "Jagruthi": ["Jagruti"],
    "L&T (Larsen & Toubro)": ["L&T", "Larsen and Toubro"],
    "MosChip Technologies": ["Moschip", "Moschip Technologies"],
    "My Home Group": ["My home", "My Home Group"],
    "NPCI": ["NPCI"],
    "Quest Global": ["Quest Global", "Quest global engineering services", "Quest Global Engineering services and Private Limited", "Quest Global Pvt. Ltd"],
    "Rajapushpa": ["Rajapushpa", "Rajapuspha"],
    "Rajapushpa Pristinia": ["Rajapusha pristina", "Rajapushpa pristinia"],
    "Rajapushpa West Avenue": ["Rajapushpa west avenue", "Rajapushpa West Avenue 115"],
    "Rajapushpa Regalia": ["Rajapushpa regalia"],
    "TCS (Tata Consultancy Services)": ["TCS", "Tata Consultancy services"],
    "Tachyon Technologies": ["Tachyon", "Tachyon technologies"],
    "BSR Infra Ventures": ["Bsrinfra", "Bsr infra ventures"],
    "HCLTech": ["HCLTECH"],
    "Oracle": ["oracle"],
    "ITC Infotech": ["Itc infotech"],
    "Aurobindo Pharma": ["Aurabindho Pharma"],
    "Holocene Ecosolutions": ["Holocene ecosolutons"],
    "Mouritech": ["Mouritech(previous)"],
    "Frameboxx Ameerpet": ["Frameboxx ammerpet"],
    "Google Operations Center": ["Google operations center"],
    "Techmojo": ["TECHMOJO"],
    "The Gallantry Group": ["THE GALLANTRY GROUP"],
    "Sri Krishna Ventures": ["SRI KRISHNA VENTURES"],
    "VRLD Infra": ["VRLD INFRA"],
    "RGUKT RK Valley": ["RGUKT RK VALLEY"],
    "Self Employed": ["Self", "Self Employed"],
    "Real Estate": ["Realestate"],
    "Indian Navy": ["Navy"],
    "HKMCF": ["HKMCF"],
    "EdXi": ["EDXi"],
    "GAR": ["Gar"],
}
# Not a college or company: left empty (occupation-like words fill Occupation when that is empty).
JUNK = ["1-40", "3 rd branch", "7 th floor", "Collage", "College", "Company", "Hostel", "Job Search", "Student", "Others", "Engineering", "Tech",
        "Pvt", "Un", "Vl", "YY", "Hw", "Gh", "Software", "School", "B-Tech", "Marketing", "Deliveries", "Shop", "Test Co", "Test College"]
AS_OCCUPATION = {key("Student"): "Student", key("Job Search"): "Job Search"}
TO_PG = {key("Cbit-mgit boys hostel"): "Cbit-mgit boys hostel"}  # a hostel typed into the college box
# Plain "NxtWave": a student means the institute (NIAT); someone working means the company.
NXTWAVE = {key(x) for x in ["NXT WAVE", "NXTWAVE", "Nxt wave", "Next wave", "Nxtwave"]}
NIAT = "NIAT - NxtWave Institute of Advanced Technologies"

BRANCHES = ["CSE", "ECE", "EEE", "Civil", "Mechanical"]
SKILLS = ["Singing", "Musical Instruments", "Video Editing", "Event Coordinator"]
INTERESTS = ["Online workshop", "Bhagavad Gita"]

alias = {}
for title, spellings in COLLEGE.items():
    for s in [title, *spellings]:
        k = key(s)
        if k in alias and alias[k] != title: raise SystemExit(f"! '{s}' is listed under two titles: {alias[k]} / {title}")
        alias[k] = title
junk = {key(x) for x in JUNK}
for k in junk:
    if k in alias: raise SystemExit(f"! '{k}' is both junk and a college")


def tidy_case(s):
    s = re.sub(r"\s+", " ", s).strip()
    if s.islower() or (s.isupper() and len(s) > 6): return " ".join(w if len(w) <= 3 and w.isupper() else w[:1].upper() + w[1:].lower() for w in s.split(" "))
    return s[:1].upper() + s[1:]


# ---------------------------------------------------------------- read
print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")
people = ok(*call("GET", "/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "mob_no", "full_name", "profession", "skills", "interests", "occupation", "pg_name", "college", "branch"])) + "&limit_page_length=0"), "read people")["data"]
print(f"people: {len(people)}")
# Re-running is safe: a new field that already has a value (set by this script or later in the app) is never overwritten.
def parents(child):
    rows = ok(*call("GET", f"/api/resource/{q(child)}?parent=FOLK%20Users&fields=" + q(json.dumps(["parent"])) + "&limit_page_length=0"), "read " + child)["data"]
    return {r["parent"] for r in rows}
has_skills, has_interests = parents("FOLK User Skill"), parents("FOLK User Interest")

fb_branch = {}
for r in sorted(json.load(open(f"{CRM}/data/feedback_contacts.json")), key=lambda x: x["created_at"]):
    p = phone(r.get("phone"))
    if p and (r.get("branch") or "").strip() in BRANCHES: fb_branch[p] = r["branch"].strip()
skill_uuid = {x["id"]: x["name"] for x in json.load(open(f"{CRM}/data/skills.json"))}

# Spellings of each value that is kept as typed: the most common spelling wins.
raw_of = defaultdict(Counter)
SUFFIX = re.compile(r"^(.*?)\s*\((" + "|".join(BRANCHES) + r")\)$")
for p in people:
    v = (p.get("profession") or "").strip()
    m = SUFFIX.match(v)
    if m: v = m.group(1).strip()
    if v: raw_of[key(v)][v] += 1


def college_of(p):
    """(title or "", branch from the suffix or "", extra fields)"""
    v = (p.get("profession") or "").strip()
    br = ""
    m = SUFFIX.match(v)
    if m: v, br = m.group(1).strip(), m.group(2)
    k = key(v)
    extra = {}
    if not k: return "", br, extra
    if k in junk:
        if k in AS_OCCUPATION and not p.get("occupation"): extra["occupation"] = AS_OCCUPATION[k]
        return "", br, extra
    if k in TO_PG:
        if not p.get("pg_name"): extra["pg_name"] = TO_PG[k]
        return "", br, extra
    if k in NXTWAVE: return ("NxtWave" if p.get("occupation") == "Working" else NIAT), br, extra
    if k in alias: return alias[k], br, extra
    return tidy_case(raw_of[k].most_common(1)[0][0]), br, extra


def multi(text, allowed, uuid=None):
    out = []
    for part in (text or "").split(","):
        s = part.strip()
        if not s: continue
        s = (uuid or {}).get(s, s)
        hit = next((a for a in allowed if key(a) == key(s)), None)
        t = hit or tidy_case(s)
        if t not in out: out.append(t)
    return out


plan = []
merged = defaultdict(Counter)  # final college title -> spellings that became it
for p in people:
    title, br, extra = college_of(p)
    if title: merged[title][re.sub(r"\s*\((" + "|".join(BRANCHES) + r")\)$", "", (p.get("profession") or "").strip())] += 1
    plan.append({"p": p, "college": title, "branch": br or fb_branch.get(p["mob_no"], ""),
                 "skills": multi(p.get("skills"), SKILLS, skill_uuid), "interests": multi(p.get("interests"), INTERESTS), "extra": extra})

# ---------------------------------------------------------------- report
print(f"\nCOLLEGE / COMPANY: {len(merged)} values (from {len(raw_of)} spellings)")
for title, c in sorted(merged.items(), key=lambda x: (-sum(x[1].values()), x[0])):
    src = ", ".join(f"{s!r}×{n}" for s, n in c.most_common())
    print(f"  {sum(c.values()):4}  {title}   <- {src}")
emptied = Counter((pl["p"].get("profession") or "").strip() for pl in plan if not pl["college"] and (pl["p"].get("profession") or "").strip())
print(f"\nleft empty (not a college/company): {sum(emptied.values())}  {dict(emptied)}")
print(f"occupation filled: {sum(1 for pl in plan if 'occupation' in pl['extra'])}, pg_name filled: {sum(1 for pl in plan if 'pg_name' in pl['extra'])}")
print(f"\nBRANCH: {dict(Counter(pl['branch'] for pl in plan if pl['branch']))}")
print(f"SKILLS: {dict(Counter(s for pl in plan for s in pl['skills']))}")
print(f"INTERESTS: {dict(Counter(s for pl in plan for s in pl['interests']))}")
extra_skills = {s for pl in plan for s in pl["skills"]} - set(SKILLS)
if extra_skills: print(f"  ! skills outside the known list: {extra_skills}")

if not COMMIT:
    print("\nDry run only. Re-run with --commit to write."); sys.exit(0)

# ---------------------------------------------------------------- write
stamp = datetime.date.today().isoformat()
os.makedirs(f"{CRM}/backups", exist_ok=True)
backup = f"{CRM}/backups/folk_users_pre_option_lists_{stamp}.json"
json.dump(people, open(backup, "w"), indent=1)
print(f"\nbackup: {backup}")


def ensure(doctype, titles):
    have = {key(r["title"]): r["name"] for r in ok(*call("GET", f"/api/resource/{q(doctype)}?fields=" + q(json.dumps(["name", "title"])) + "&limit_page_length=0"), "read " + doctype)["data"]}
    ids = {}
    for t in sorted(set(titles)):
        if key(t) not in have:
            s, r = call("POST", f"/api/resource/{q(doctype)}", {"title": t})
            if s != 200: raise SystemExit(f"! add {doctype} {t!r}: {s} {r}")
            have[key(t)] = r["data"]["name"]
        ids[t] = have[key(t)]
    print(f"  {doctype}: {len(ids)} values")
    return ids


cid = ensure("FOLK College", [pl["college"] for pl in plan if pl["college"]])
bid = ensure("FOLK Branch", BRANCHES)
sid = ensure("FOLK Skill", SKILLS + [s for pl in plan for s in pl["skills"]])
iid = ensure("FOLK Interest", INTERESTS + [s for pl in plan for s in pl["interests"]])

docs = []
for pl in plan:
    if not (pl["college"] or pl["branch"] or pl["skills"] or pl["interests"] or pl["extra"]): continue
    p = pl["p"]
    d = {"doctype": "FOLK Users", "docname": p["name"], **pl["extra"]}
    if pl["college"] and not p.get("college"): d["college"] = cid[pl["college"]]
    if pl["branch"] and not p.get("branch"): d["branch"] = bid[pl["branch"]]
    if pl["skills"] and p["name"] not in has_skills: d["skill_list"] = [{"skill": sid[s]} for s in pl["skills"]]
    if pl["interests"] and p["name"] not in has_interests: d["interest_list"] = [{"interest": iid[s]} for s in pl["interests"]]
    if len(d) > 2: docs.append(d)
print(f"updating {len(docs)} people")
failed = []
for i in range(0, len(docs), 100):
    part = docs[i:i + 100]
    s, r = call("POST", "/api/method/frappe.client.bulk_update", {"docs": json.dumps(part)})
    bad = (r.get("message") or {}).get("failed_docs") if s == 200 else part
    if bad: failed += bad
    print(f"  {i + 1}-{i + len(part)}:", "ok" if s == 200 and not bad else f"! {s} {len(bad)} failed")
if failed: print("FAILED:", json.dumps(failed)[:2000])

# Hide the old text fields in ERPNext (values kept) so only the dropdown fields are edited from now on.
doc = ok(*call("GET", "/api/resource/DocType/FOLK%20Users"), "read DocType")["data"]
for f in doc["fields"]:
    if f["fieldname"] in ("profession", "skills", "interests"):
        f["hidden"] = 1; f["read_only"] = 1
        if not f["label"].startswith("Old "): f["label"] = "Old " + f["label"] + " (text)"
ok(*call("PUT", "/api/resource/DocType/FOLK%20Users", doc), "hide old fields")
print("old text fields hidden. Done.")
