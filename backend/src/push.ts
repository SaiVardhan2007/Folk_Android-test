// Phone notifications through Firebase Cloud Messaging (HTTP v1). The service-account key is the Worker secret FCM_SERVICE_ACCOUNT (the JSON file, as text).
// Without that secret every send is skipped, so the rest of the app is unaffected.
import type { Bindings } from "./types";
import type { Erp } from "./erp";

export const DEVICE = "FOLK Device";
type Account = { project_id: string; client_email: string; private_key: string };

const b64url = (b: ArrayBuffer | string) => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = "";
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

let cached: { token: string; until: number } | null = null;

async function accessToken(a: Account): Promise<string> {
  if (cached && cached.until > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({ iss: a.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
  const pem = a.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const key = await crypto.subtle.importKey("pkcs8", Uint8Array.from(atob(pem), (ch) => ch.charCodeAt(0)), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${claim}`));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${head}.${claim}.${b64url(sig)}` }),
  });
  if (!res.ok) throw new Error(`fcm auth ${res.status}`);
  const j = (await res.json()) as { access_token: string; expires_in: number };
  cached = { token: j.access_token, until: Date.now() + j.expires_in * 1000 };
  return j.access_token;
}

/** Sends one notification to every phone of the given people. Phones Firebase says are gone are removed. Never throws. */
export async function pushTo(env: Bindings, erp: Erp, people: string[], title: string, body: string, data: Record<string, string> = {}): Promise<number> {
  if (!env.FCM_SERVICE_ACCOUNT || !people.length) return 0;
  try {
    const acct = JSON.parse(env.FCM_SERVICE_ACCOUNT) as Account;
    const devices = await erp.list<{ name: string; token: string }>(DEVICE, ["name", "token"], [["person", "in", people]]);
    if (!devices.length) return 0;
    const auth = await accessToken(acct);
    let sent = 0;
    await Promise.all(devices.map(async (d) => {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${acct.project_id}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${auth}`, "Content-Type": "application/json" },
        body: JSON.stringify({ message: { token: d.token, notification: { title, body }, data, android: { priority: "HIGH" } } }),
      });
      if (res.ok) { sent++; return; }
      const t = await res.text();
      console.log(`push to ${d.name} failed ${res.status} ${t.slice(0, 160)}`);
      if (res.status === 404 || /UNREGISTERED|INVALID_ARGUMENT/.test(t)) await erp.remove(DEVICE, d.name).catch(() => {});
    }));
    return sent;
  } catch (e) {
    console.error("push", e);
    return 0;
  }
}
