"""Adds FOLK Settings.import_sources (saved Google Sheet import sources, JSON). Re-runnable."""
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


def add_fields(doctype, specs, after_field):
    s, d = call("GET", "/api/resource/DocType/" + doctype.replace(" ", "%20"))
    doc = d["data"]; fields = doc["fields"]; have = {f["fieldname"] for f in fields}
    idx = next((i for i, f in enumerate(fields) if f["fieldname"] == after_field), len(fields) - 1)
    changed = False
    for spec in specs:
        if spec["fieldname"] not in have:
            idx += 1; fields.insert(idx, spec); changed = True; print("+", doctype, spec["fieldname"])
    if changed:
        s, r = call("PUT", "/api/resource/DocType/" + doctype.replace(" ", "%20"), doc)
        print("saved" if s == 200 else f"! {s} {r}")
    else:
        print("=", doctype, "already up to date")


add_fields("FOLK Settings", [
    {"fieldname": "import_sources", "label": "Saved import sources (JSON)", "fieldtype": "Long Text"},
], "message_templates")
