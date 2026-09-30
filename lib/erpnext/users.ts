// App accounts live on the person's FOLK Users: the mobile number is the login ID, password_hash holds the
// PBKDF2 hash (never the password) and user_tag holds their tag.
import { docPath, erp, getDoc, list } from "./client";
import { asTag, DEFAULT_TAGS, type Tag } from "@/lib/roles";
import { hashPassword, verifyPassword } from "@/lib/password";
import { normalizeMobile } from "@/lib/utils";
import { PAGE_SIZE, peopleFilters, searchFilters, SORTS, type PeopleQuery } from "@/lib/admin-query";

export type Access = { mob: string; name: string; tag: Tag };
type Result = { ok: true; user: Access } | { ok: false; message: string };
type RegRow = { mob_no: string; full_name: string; user_tag?: string; password_hash?: string };

const DOCTYPE = "FOLK Users";
const userPath = (mob: string) => docPath(DOCTYPE, mob);
export const MIN_PASSWORD = 8;

const getRow = (mob: string) => getDoc<RegRow>(DOCTYPE, mob);
const access = (r: RegRow): Access => ({ mob: r.mob_no, name: r.full_name, tag: asTag(r.user_tag) });

// ---- sign-in

/** Current access for a signed-in mobile, read fresh so tag changes apply immediately. Null = not allowed in. */
export async function getAccess(mob: string) {
  const r = await getRow(mob);
  return r?.password_hash ? access(r) : null;
}

export async function verifyLogin(rawMob: string, password: string): Promise<Result> {
  const mob = normalizeMobile(rawMob);
  const r = mob ? await getRow(mob) : null;
  const good = await verifyPassword(password, r?.password_hash); // runs even with no hash, to keep timing uniform
  if (!r || !good) {
    // A registered number with no password yet should be told to create one, not "incorrect".
    if (r && !r.password_hash) return { ok: false, message: "No password yet for this number. Use “Create password”." };
    return { ok: false, message: "Incorrect mobile number or password." };
  }
  return { ok: true, user: access(r) };
}

/** First-time setup: sets the password on an existing registration, or registers a new person (as People). */
export async function createAccount(rawMob: string, name: string, password: string): Promise<Result> {
  const mob = normalizeMobile(rawMob);
  if (!mob) return { ok: false, message: "Enter a valid 10-digit mobile number." };
  if (password.length < MIN_PASSWORD) return { ok: false, message: `Password must be at least ${MIN_PASSWORD} characters.` };
  const password_hash = await hashPassword(password);
  const r = await getRow(mob);
  if (r?.password_hash) return { ok: false, message: "This number already has a password. Sign in instead." };
  if (r) {
    await erp("PUT", userPath(mob), { password_hash });
    return { ok: true, user: access(r) };
  }
  name = name.trim();
  if (!name) return { ok: false, message: "Enter your name." };
  await erp("POST", docPath(DOCTYPE), { name: mob, mob_no: mob, full_name: name, user_tag: "People", registered_by: "self sign-up", password_hash });
  return { ok: true, user: { mob, name, tag: "People" } };
}

// ---- Admin: people list

export type Person = {
  mob_no: string; full_name: string; user_tag: Tag; has_password: boolean;
  level: string; gender: string; event_code: string; attendance_count: number; last_attended_on: string; creation: string;
};

const PERSON_FIELDS = ["mob_no", "full_name", "user_tag", "password_hash", "level", "gender", "event_code", "attendance_count", "last_attended_on", "creation"];
type PersonRow = RegRow & Partial<Record<"level" | "gender" | "event_code" | "last_attended_on" | "creation", string>> & { attendance_count?: number };

/** One page of people matching the query, plus the total. Never returns the hash itself. */
export async function queryPeople(q: PeopleQuery): Promise<{ people: Person[]; total: number }> {
  const filters = peopleFilters(q);
  const or_filters = searchFilters(q.q);
  // Two parallel calls: the page of rows, and just the names of every match (to get the total for paging).
  const [rows, names] = await Promise.all([
    list<PersonRow>(DOCTYPE, PERSON_FIELDS, filters, { order_by: SORTS[q.sort].order, limit_page_length: PAGE_SIZE, limit_start: (q.page - 1) * PAGE_SIZE, ...(or_filters && { or_filters }) }),
    list<{ name: string }>(DOCTYPE, ["name"], filters, or_filters ? { or_filters } : {}),
  ]);
  return {
    total: names.length,
    people: rows.map((r) => ({
      mob_no: r.mob_no, full_name: r.full_name, user_tag: asTag(r.user_tag), has_password: !!r.password_hash,
      level: r.level ?? "", gender: r.gender ?? "", event_code: r.event_code ?? "", attendance_count: r.attendance_count ?? 0,
      last_attended_on: r.last_attended_on ?? "", creation: (r.creation ?? "").slice(0, 10),
    })),
  };
}

/** Tags defined on the user_tag field in ERPNext, in the order set there. Falls back to the defaults if unreachable. */
export async function getTagOptions(): Promise<string[]> {
  try {
    const r = await erp("GET", docPath("DocType", DOCTYPE));
    const field = (r.data.fields as { fieldname: string; options?: string }[]).find((f) => f.fieldname === "user_tag");
    const opts = (field?.options ?? "").split("\n").map((o) => o.trim()).filter(Boolean);
    return opts.length ? opts : DEFAULT_TAGS;
  } catch (e) {
    console.error(e);
    return DEFAULT_TAGS;
  }
}

export const setTag = (mob: string, tag: Tag) => erp("PUT", userPath(mob), { user_tag: tag });
/** Clears the password so the person can create a new one from the login page. */
export const resetPassword = (mob: string) => erp("PUT", userPath(mob), { password_hash: "" });
