// Registration rules shared by the Register screen and the Attendance screen (which can register on the spot).
import "server-only";
import * as erp from "@/lib/erpnext";
import { LEVELS, type Level } from "@/lib/erpnext";
import { normalizeMobile } from "@/lib/utils";
import type { Result } from "@/lib/result";

/** Reads and cleans the registration fields from a submitted form. Invalid gender/level become "". */
export function readRegistrationFields(form: FormData) {
  const get = (k: string) => String(form.get(k) ?? "").trim();
  const gender = get("gender");
  const level = get("level");
  return {
    mob_no: normalizeMobile(get("mob_no")),
    full_name: get("full_name"),
    gender: gender === "M" || gender === "F" ? gender : "",
    level: (LEVELS as readonly string[]).includes(level) ? (level as Level) : "",
    pg_name: get("pg_name"),
    profession: get("profession"),
    event_code: get("event_code"),
  };
}
export type RegistrationFields = ReturnType<typeof readRegistrationFields>;

/** ERPNext's "duplicate entry" error, e.g. two people registering the same number at once. */
export const isDuplicate = (e: unknown) => /duplicate|unique/i.test(String((e as Error)?.message));

/** Validates and creates a registration. Returns an error Result, or null on success. */
export async function createRegistrationChecked(f: RegistrationFields, registeredBy: string): Promise<Result | null> {
  if (!f.mob_no) return { ok: false, message: "Enter a valid 10-digit mobile number." };
  if (!f.full_name) return { ok: false, message: "Name is required." };
  if (!f.level) return { ok: false, message: "Select a level." };
  if (await erp.getRegistration(f.mob_no)) return { ok: false, message: "This mobile number is already registered." };
  try {
    await erp.createRegistration({ ...f, name: f.mob_no, event_code: f.event_code || undefined, registered_by: registeredBy, user_tag: "People" });
  } catch (e) {
    if (isDuplicate(e)) return { ok: false, message: "This mobile number is already registered." };
    throw e;
  }
  return null;
}
