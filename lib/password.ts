// PBKDF2 via Web Crypto so it runs on Cloudflare Workers (which caps iterations at 100000).
const ITER = 100_000;
const hex = (b: ArrayBuffer | Uint8Array) => Array.from(new Uint8Array(b), (x) => x.toString(16).padStart(2, "0")).join("");
const unhex = (s: string) => Uint8Array.from(s.match(/../g) ?? [], (h) => parseInt(h, 16));

async function derive(password: string, salt: Uint8Array, iter: number) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(password), "PBKDF2", false, ["deriveBits"]);
  return hex(await crypto.subtle.deriveBits({ name: "PBKDF2", hash: "SHA-256", salt: salt as BufferSource, iterations: iter }, key, 256));
}

/** -> "pbkdf2$<iterations>$<salt hex>$<hash hex>" */
export async function hashPassword(password: string) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  return `pbkdf2$${ITER}$${hex(salt)}$${await derive(password, salt, ITER)}`;
}

export async function verifyPassword(password: string, stored: string | null | undefined) {
  const [scheme, iter, salt, want] = (stored ?? "").split("$");
  // Still do the work when there is no stored hash, so timing doesn't reveal which emails exist.
  const got = await derive(password, salt ? unhex(salt) : new Uint8Array(16), Number(iter) || ITER);
  if (scheme !== "pbkdf2" || !want || got.length !== want.length) return false;
  let diff = 0;
  for (let i = 0; i < got.length; i++) diff |= got.charCodeAt(i) ^ want.charCodeAt(i);
  return diff === 0;
}
