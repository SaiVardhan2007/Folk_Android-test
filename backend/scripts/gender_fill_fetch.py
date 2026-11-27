"""Read-only: saves every person with an empty gender to a JSON file (path given as argument)."""
import json, os, sys, urllib.parse, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
def get(path):
    return json.loads(urllib.request.urlopen(urllib.request.Request(env["ERPNEXT_URL"] + path, headers=H), timeout=120).read())
q = urllib.parse.quote
rows = get("/api/resource/FOLK%20Users?fields=" + q(json.dumps(["name", "mob_no", "full_name", "gender", "user_tag"])) + "&filters=" + q(json.dumps([["gender", "in", ["", None]]])) + "&limit_page_length=0")["data"]
total = get("/api/method/frappe.client.get_count?doctype=FOLK%20Users")["message"]
json.dump(rows, open(sys.argv[1], "w"), ensure_ascii=False)
print("total people", total, "| empty gender", len(rows))
