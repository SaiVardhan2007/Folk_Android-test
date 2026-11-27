"""Phone notification tokens: FOLK Device (one row per phone that can receive notifications). Re-runnable.

  python3 -I scripts/phase24_devices.py            dry run: writes NOTHING
  python3 -I scripts/phase24_devices.py --commit   really writes
"""
import json, os, sys, urllib.request, urllib.error

COMMIT = "--commit" in sys.argv
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


print("DRY RUN (nothing is written)" if not COMMIT else "COMMIT")
s, _ = call("GET", "/api/resource/DocType/FOLK%20Device")
if s == 200:
    print("= FOLK Device already exists")
else:
    print("+ DocType FOLK Device")
    if COMMIT:
        s, r = call("POST", "/api/resource/DocType", {
            "doctype": "DocType", "name": "FOLK Device", "module": "Custom", "custom": 1,
            "description": "A phone signed in to the app that can receive notifications (Firebase token).",
            "autoname": "hash", "naming_rule": "Random", "sort_field": "modified", "sort_order": "DESC",
            "permissions": [{"role": "System Manager", "read": 1, "write": 1, "create": 1, "delete": 1, "export": 1, "report": 1, "share": 1}],
            "fields": [
                {"fieldname": "token", "label": "Token", "fieldtype": "Small Text", "reqd": 1, "in_list_view": 1},
                {"fieldname": "token_key", "label": "Token Key", "fieldtype": "Data", "unique": 1, "reqd": 1, "description": "First 140 characters of the token (unique)"},
                {"fieldname": "person", "label": "Person", "fieldtype": "Link", "options": "FOLK Users", "reqd": 1, "in_list_view": 1},
                {"fieldname": "platform", "label": "Platform", "fieldtype": "Data"},
            ],
        })
        if s != 200: raise SystemExit(f"! create FOLK Device: {s} {r}")
print("done" if COMMIT else "dry run finished: re-run with --commit")
