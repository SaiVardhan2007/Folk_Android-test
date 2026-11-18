// Password hashing (same format the web app used, so existing accounts keep working) and signed tokens.
const ITER = 100_000; // Cloudflare Workers caps PBKDF2 at 100000 iterations
const hex = (b: ArrayBuffer | Uint8Array) => Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join("");
const unhex = (s: string) => Uint8Array.from(s.match(/../g) ?? [], (h) => parseInt(h, 16));
const te = new TextEncoder();

async function derive(password: string, salt: Uint8Array, iter: number) {
  const key = await crypto.subtle.importKey("raw", te.encode(password), "PBKDF2", false, ["deriveBits"]);
  return hex(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: salt as BufferSource, iterations: iter }, key, 256));
}

/** -> "pbkdf2$<iterations>$<salt hex>$<hash hex>" */
export async function hashPassword(password: string) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return `pbkdf2$${ITER}$${hex(salt)}$${await derive(password, salt, ITER)}`;
}

export async function verifyPassword(password: string, stored: string | null | undefined) {
  const [scheme, iter, salt, want] = (stored ?? "").split("$");
  // Do the work even when there is no hash, so timing doesn't reveal which numbers exist.
  const got = await derive(password, salt ? unhex(salt) : new Uint8Array(16), Math.min(Number(iter) || ITER, ITER));
  if (scheme !== "pbkdf2" || !want || got.length !== want.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ want.charCodeAt(i);
  return diff === 0;
}

/** Cheap fast hash for short one-time reset codes (the code is random, single-use and expires). */
export async function sha256Hex(s: string) {
  return hex(await crypto.subtle.digest("SHA-256", te.encode(s)));
}

export function randomCode() {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return String(n).padStart(6, "0");
}

// ---- HS256 JWT
const b64u = (b: ArrayBuffer | Uint8Array) => btoa(String.fromCharCode(...new Uint8Array(b))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64uStr = (s: string) => b64u(te.encode(s));
const fromB64u = (s: string) => atob(s.replace(/-/g, "+").replace(/_/g, "/"));

const hmacKey = (secret: string) => crypto.subtle.importKey("raw", te.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);

export async function signToken(payload: Record<string, unknown>, secret: string, ttlSeconds: number) {
  const now = Math.floor(Date.now() / 1000);
  const head = b64uStr(JSON.stringify({ alg: "HS256", typ: "JWT" }));
  const body = b64uStr(JSON.stringify({ ...payload, iat: now, exp: now + ttlSeconds }));
  const sig = b64u(await crypto.subtle.sign("HMAC", await hmacKey(secret), te.encode(`${head}.${body}`)));
  return `${head}.${body}.${sig}`;
}

export async function verifyToken(token: string, secret: string): Promise<Record<string, unknown> | null> {
  const [head, body, sig] = token.split(".");
  if (!head || !body || !sig) return null;
  try {
    const bytes = Uint8Array.from(fromB64u(sig), (c) => c.charCodeAt(0));
    const ok = await crypto.subtle.verify("HMAC", await hmacKey(secret), bytes, te.encode(`${head}.${body}`));
    if (!ok) return null;
    const payload = JSON.parse(fromB64u(body));
    if (typeof payload.exp !== "number" || payload.exp < Date.now() / 1000) return null;
    return payload;
  } catch {
    return null;
  }
}
