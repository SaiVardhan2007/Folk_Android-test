// A person is one FOLK Users record (ID = mobile number). Their attendance rows live inside it (child table).
import { count, docPath, erp, getDoc, list } from "./client";
import type { AttendanceEntry } from "./attendance";
import type { Level } from "@/lib/levels";

export { LEVELS, type Level } from "@/lib/levels";

const DOCTYPE = "FOLK Users";

export type Registration = {
  name: string; // = mob_no
  mob_no: string;
  full_name: string;
  gender?: "M" | "F" | "";
  level?: Level | "";
  pg_name?: string;
  profession?: string;
  event_code?: string;
  attendance_count?: number;
  modified?: string; // ERPNext's edit stamp; sent back on save so concurrent edits are detected
  attendance?: AttendanceEntry[];
};

/** The person with this mobile number, or null. The password hash is stripped so it can't leak to pages. */
export async function getRegistration(mob: string) {
  const reg = await getDoc<Registration & { password_hash?: string }>(DOCTYPE, mob);
  if (reg) delete reg.password_hash;
  return reg as Registration | null;
}
export const createRegistration = (d: Record<string, unknown>) =>
  erp("POST", docPath(DOCTYPE), d).then((r) => r.data as Registration);
export const updateRegistration = (mob: string, d: Record<string, unknown>) =>
  erp("PUT", docPath(DOCTYPE, mob), d);
export const countRegistrations = (event: string) => count(DOCTYPE, [["event_code", "=", event]]);

// ---- CSV export (Reports page)
export const REGISTRATION_CSV_COLS = ["mob_no", "full_name", "gender", "level", "pg_name", "profession", "event_code", "attendance_count", "registered_by", "creation"];
export const allRegistrations = (event: string) =>
  list<Registration>(DOCTYPE, REGISTRATION_CSV_COLS, [["event_code", "=", event]], { order_by: "creation asc" });
