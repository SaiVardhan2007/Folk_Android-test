// Signed-cookie session (HMAC via Web Crypto, so it runs on Cloudflare Workers).
// Credentials are checked against the person's FOLK Users (see lib/erpnext/users.ts). The cookie only proves who you are;
// your tag is looked up fresh on every request, so an Admin's change (or removal) applies immediately.
import "server-only";
import { cache } from "react";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";
import { getAccess } from "@/lib/erpnext/users";
import type { Tag } from "@/lib/roles";

const COOKIE = "folk_session";
const MAX_AGE = 60 * 60 * 12; // 12 hours

export type Session = { mob: string; name: string; tag: Tag };

const b64 = (bytes: Uint8Array) => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64 = (s: string) => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/")), (c) => c.charCodeAt(0));

/** HMAC-SHA256 of `value` with SESSION_SECRET, base64url-encoded. */
async function sign(value: string) {
  const secret = process.env.SESSION_SECRET;
  if (!secret) throw new Error("SESSION_SECRET is not set");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return b64(new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value))));
}

/** Constant-time string compare, so a forged signature can't be guessed byte by byte from response timing. */
function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/** Cookie format: "<base64url payload>.<signature>", payload = { m: mobile, n: name, x: expiry ms }. */
export async function createSession(s: { mob: string; name: string }) {
  const payload = b64(new TextEncoder().encode(JSON.stringify({ m: s.mob, n: s.name, x: Date.now() + MAX_AGE * 1000 })));
  (await cookies()).set(COOKIE, `${payload}.${await sign(payload)}`, {
    httpOnly: true, secure: process.env.NODE_ENV === "production", sameSite: "lax", maxAge: MAX_AGE, path: "/",
  });
}

export async function destroySession() {
  (await cookies()).delete(COOKIE);
}

/** The signed-in user (fresh from ERPNext), or null. Cached per request, so calling it many times is free. */
export const getSession = cache(async (): Promise<Session | null> => {
  const v = (await cookies()).get(COOKIE)?.value;
  if (!v) return null;
  const [payload, sig] = v.split(".");
  if (!payload || !sig || !safeEqual(await sign(payload), sig)) return null;
  try {
    const p = JSON.parse(new TextDecoder().decode(unb64(payload))) as { m: string; n: string; x: number };
    if (p.x < Date.now()) return null;
    const a = await getAccess(p.m);
    return a ? { mob: a.mob, name: a.name, tag: a.tag } : null;
  } catch {
    return null;
  }
});

/** Use at the top of pages, server actions and route handlers that need a signed-in user. */
export async function requireSession() {
  const s = await getSession();
  if (!s) redirect("/login");
  return s;
}

/** Admin-only pages and actions. */
export async function requireAdmin() {
  const s = await requireSession();
  if (s.tag !== "Admin") redirect("/");
  return s;
}
