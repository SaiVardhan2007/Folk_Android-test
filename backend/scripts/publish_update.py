"""Tells phones a new build exists: sets FOLK Settings.app_update (latest build, message), keeping the saved download link and minimum build.
Used by tool/release.sh.   python3 -I scripts/publish_update.py <build> "<message>" [--min]   (--min makes this build mandatory)
"""
import json, os, sys, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
env = dict(l.strip().split("=", 1) for l in open(os.path.join(HERE, "..", ".dev.vars")) if "=" in l)
H = {"Authorization": f"token {env['ERPNEXT_API_KEY']}:{env['ERPNEXT_API_SECRET']}", "Content-Type": "application/json", "User-Agent": "folk-setup/1.0", "Accept": "application/json"}
URL = env["ERPNEXT_URL"] + "/api/resource/FOLK%20Settings/FOLK%20Settings"
build, message = int(sys.argv[1]), sys.argv[2][:300]
cur = json.loads(urllib.request.urlopen(urllib.request.Request(URL, headers=H), timeout=60).read())["data"].get("app_update")
u = json.loads(cur) if cur else {}
u.update({"latest_build": build, "message": message})
if "--min" in sys.argv: u["min_build"] = build
if not u.get("url"): raise SystemExit("! no download link saved yet: set it once in Admin > Settings > App update")
urllib.request.urlopen(urllib.request.Request(URL, method="PUT", headers=H, data=json.dumps({"app_update": json.dumps(u)}).encode()), timeout=60).read()
print("phones will be offered build", build, "(mandatory)" if "--min" in sys.argv else "")
