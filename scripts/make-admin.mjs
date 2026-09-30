// Makes someone an Admin (or Coordinator): creates their FOLK Users if needed and sets user_tag.
// They then create their own password on the login page. Only set PASSWORD if you want to set it here instead.
// Usage: [TAG=Coordinator] MOB=9876543210 NAME="Full Name" [PASSWORD='8+ chars'] npm run erpnext:make-admin
import { readFileSync } from "node:fs";
import { webcrypto as crypto } from "node:crypto";

try {
  for (const line of readFileSync(".env.local", "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)\s*$/);
    if (m && !process.env[m[1]]) process.env[m[1]] = m[2].replace(/^["']|["']$/g, "");
  }
} catch {}

const base = (process.env.ERPNEXT_URL || "").replace(/\/$/, "");
const key = process.env.SETUP_API_KEY || process.env.ERPNEXT_API_KEY, secret = process.env.SETUP_API_SECRET || process.env.ERPNEXT_API_SECRET;
const { MOB, NAME, PASSWORD } = process.env;
const TAG = process.env.TAG || "Admin";
if (!base || !key || !secret) { console.error("Missing ERPNEXT_URL / ERPNEXT_API_KEY / ERPNEXT_API_SECRET in .env.local."); process.exit(1); }
if (!["Admin", "Coordinator"].includes(TAG)) { console.error("TAG must be Admin or Coordinator."); process.exit(1); }
if (!/^\d{10}$/.test(MOB ?? "") || !NAME || (PASSWORD && PASSWORD.length < 8)) { console.error("Set MOB (10 digits) and NAME; PASSWORD (if given) must be 8+ chars."); process.exit(1); }

const hex = (b) => Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join("");
async function hash(pw) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(pw), "PBKDF2", false, ["deriveBits"]);
  return `pbkdf2$100000$${hex(salt)}$${hex(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt, iterations: 100000 }, k, 256))}`;
}

const call = async (method, path, body) => {
  const res = await fetch(`${base}${path}`, { method, headers: { Authorization: `token ${key}:${secret}`, "Content-Type": "application/json" }, body: body ? JSON.stringify(body) : undefined });
  return { ok: res.ok, status: res.status, text: await res.text() };
};
const must = (r, what) => { if (!r.ok) { console.error(`x ${what} (HTTP ${r.status})\n${r.text.slice(0, 600)}`); process.exit(1); } console.log(`+ ${what}`); };

const extra = PASSWORD ? { password_hash: await hash(PASSWORD) } : {};
const reg = await call("GET", `/api/resource/FOLK%20Users/${MOB}`);
if (reg.ok) must(await call("PUT", `/api/resource/FOLK%20Users/${MOB}`, { user_tag: TAG, ...extra }), `Set ${MOB} to ${TAG}`);
else must(await call("POST", "/api/resource/FOLK%20Users", { name: MOB, mob_no: MOB, full_name: NAME, user_tag: TAG, registered_by: "make-admin", ...extra }), `Created registration ${MOB} as ${TAG}`);
if (!PASSWORD) console.log(`${MOB} should now open the login page and choose "First time here? Create password".`);
