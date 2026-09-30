// Creates the FOLK DocTypes in ERPNext through its REST API. Existing DocTypes are never modified.
// Usage: npm run erpnext:setup   (reads .env.local)
import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";

function loadEnv(file) {
  try {
    for (const line of readFileSync(file, "utf8").split("\n")) {
      const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
      if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
    }
  } catch {}
}
loadEnv(".env.local");

const base = (process.env.SETUP_ERPNEXT_URL || process.env.ERPNEXT_URL || "").replace(/\/$/, "");
const key = process.env.SETUP_API_KEY || process.env.ERPNEXT_API_KEY;
const secret = process.env.SETUP_API_SECRET || process.env.ERPNEXT_API_SECRET;
if (!base || !key || !secret) {
  console.error("Missing SETUP_ERPNEXT_URL / SETUP_API_KEY / SETUP_API_SECRET in .env.local (see docs/ERPNEXT_SETUP.md, step 2).");
  process.exit(1);
}

const headers = { Authorization: `token ${key}:${secret}`, "Content-Type": "application/json" };

async function call(method, path, body) {
  const res = await fetch(`${base}${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  let json; try { json = JSON.parse(text); } catch {}
  return { ok: res.ok, status: res.status, json, text };
}

async function ensure(doctype, name, doc) {
  const exists = await call("GET", `/api/resource/${encodeURIComponent(doctype)}/${encodeURIComponent(name)}`);
  if (exists.ok) return console.log(`= ${doctype} "${name}" already exists, skipped`);
  const r = await call("POST", `/api/resource/${encodeURIComponent(doctype)}`, doc);
  if (!r.ok) {
    console.error(`x Failed to create ${doctype} "${name}" (HTTP ${r.status})\n${r.text.slice(0, 800)}`);
    process.exit(1);
  }
  console.log(`+ Created ${doctype} "${name}"`);
}

const dir = "erpnext/doctypes";
// Order matters: the attendance table and FOLK Users link to Event, and FOLK Users uses the table.
const order = ["folk-event.json", "folk-users-attendance.json", "folk-users.json", "folk-settings.json"];
for (const f of order.concat(readdirSync(dir).filter((x) => !order.includes(x)))) {
  const doc = JSON.parse(readFileSync(join(dir, f), "utf8"));
  await ensure("DocType", doc.name, doc);
}
console.log("\nDone. Next: create the first Admin with `npm run erpnext:make-admin`.");
