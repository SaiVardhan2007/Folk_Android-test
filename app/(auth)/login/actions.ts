"use server";

import { createSession } from "@/lib/auth";
import { createAccount, verifyLogin } from "@/lib/erpnext";
import type { Result } from "@/lib/result";

const field = (form: FormData, k: string) => String(form.get(k) ?? "");

/** Runs a sign-in / sign-up check and, if it passes, starts the session. Errors never leak details to the browser. */
async function run(fn: () => ReturnType<typeof verifyLogin>): Promise<Result> {
  try {
    const r = await fn();
    if (!r.ok) return r;
    await createSession(r.user);
  } catch (e) {
    console.error(e);
    return { ok: false, message: "Couldn't reach the server. Try again." };
  }
  return { ok: true, message: "Signed in" };
}

export async function loginAction(_: Result | null, form: FormData): Promise<Result> {
  const mob = field(form, "mob_no").trim(), password = field(form, "password");
  if (!mob || !password) return { ok: false, message: "Enter your mobile number and password." };
  return run(() => verifyLogin(mob, password));
}

/** First time only: choose a password (and give a name if this number was never registered). */
export async function createAccountAction(_: Result | null, form: FormData): Promise<Result> {
  const mob = field(form, "mob_no").trim(), password = field(form, "password");
  if (password !== field(form, "confirm")) return { ok: false, message: "Passwords don't match." };
  return run(() => createAccount(mob, field(form, "full_name"), password));
}
