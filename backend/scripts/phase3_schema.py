"""Phase A schema: contact fields, unique mobile, generated IDs (FP-#####), roles Public/Coordinator/Admin. Re-runnable."""
import json, os, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json",
     "User-Agent": "folk-setup/1.0", "Accept": "application/json"}


def call(method, path, body=None):
    req = urllib.request.Request(env["ERPNEXT_URL"] + path, method=method, headers=H, data=json.dumps(body).encode() if body is not None else None)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:800]}


s, d = call("GET", "/api/resource/DocType/FOLK%20Users")
doc = d["data"]
fields = doc["fields"]
have = {f["fieldname"] for f in fields}

new = [
    ("venue", "Venue", "Data", {}),
    ("gmap_link", "Google Map Link", "Data", {"options": "URL"}),
    ("call_no", "Call Number", "Data", {"description": "Number the person is told to call (sent in the WhatsApp message)"}),
    ("fg_name", "FOLK Guide Name", "Data", {}),
    ("fg_mob_no", "FOLK Guide Mobile", "Data", {}),
]
after = next(i for i, f in enumerate(fields) if f["fieldname"] == "event_code")
for fn, label, ft, extra in new:
    if fn not in have:
        after += 1
        fields.insert(after, {"fieldname": fn, "label": label, "fieldtype": ft, **extra})
        print("+ field", fn)

for f in fields:
    if f["fieldname"] == "mob_no":
        f["unique"] = 1; f["reqd"] = 1; f["in_list_view"] = 1; f["in_standard_filter"] = 1
    if f["fieldname"] == "user_tag":
        f["label"] = "Role"; f["options"] = "Public\nCoordinator\nAdmin"; f["default"] = "Public"

doc["autoname"] = "FP-.#####"
doc["naming_rule"] = "Expression (old style)"
doc["allow_rename"] = 1
s, r = call("PUT", "/api/resource/DocType/FOLK%20Users", doc)
print("schema saved" if s == 200 else f"! {s} {r}")
