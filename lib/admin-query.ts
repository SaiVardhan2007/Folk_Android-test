// Shared by the Admin People page and its CSV export: turns URL params into a validated query.
import { GENDERS } from "@/lib/genders";
import { LEVELS } from "@/lib/levels";
import { TAGS } from "@/lib/roles";

export const PAGE_SIZE = 25;
const GENDER_VALUES = GENDERS.map((g) => g.value);
const DATE = /^\d{4}-\d{2}-\d{2}$/;

export const SORTS = {
  newest: { label: "Newest first", order: "creation desc" },
  oldest: { label: "Oldest first", order: "creation asc" },
  name: { label: "Name A–Z", order: "full_name asc" },
  most: { label: "Most attended", order: "attendance_count desc" },
  recent: { label: "Recently attended", order: "last_attended_on desc" },
} as const;

export type PeopleQuery = {
  q: string; tag: string; level: string; gender: string; event: string;
  pw: "" | "set" | "unset"; att: "" | "yes" | "no"; from: string; to: string;
  sort: keyof typeof SORTS; page: number;
};

/** Next.js `searchParams`: each value is a string, a repeated param (array) or missing. */
export type SearchParams = Record<string, string | string[] | undefined>;
/** First value of a URL param, or "". */
export const one = (v: string | string[] | undefined) => (Array.isArray(v) ? v[0] : v) ?? "";
const pick = <T extends string>(v: string, allowed: readonly T[]) => (allowed as readonly string[]).includes(v) ? (v as T) : ("" as T);
export const validDate = (v: string) => (DATE.test(v) ? v : "");

/** Reads and validates the Admin People URL params; anything unknown or malformed falls back to "no filter". */
export function parsePeopleQuery(sp: SearchParams): PeopleQuery {
  const sort = one(sp.sort);
  return {
    q: one(sp.q).trim(), tag: pick(one(sp.tag), TAGS), level: pick(one(sp.level), LEVELS), gender: pick(one(sp.gender), GENDER_VALUES),
    event: one(sp.event).trim(), pw: pick(one(sp.pw), ["set", "unset"]), att: pick(one(sp.att), ["yes", "no"]),
    from: validDate(one(sp.from)), to: validDate(one(sp.to)),
    sort: sort in SORTS ? (sort as keyof typeof SORTS) : "newest",
    page: Math.max(1, Number.parseInt(one(sp.page)) || 1),
  };
}

/** ERPNext filters for a query (search is separate: it needs or_filters). */
export function peopleFilters(q: PeopleQuery): unknown[][] {
  const f: unknown[][] = [];
  if (q.tag) f.push(["user_tag", "=", q.tag]);
  if (q.level) f.push(["level", "=", q.level]);
  if (q.gender) f.push(["gender", "=", q.gender]);
  if (q.event) f.push(["event_code", "=", q.event]);
  if (q.pw === "set") f.push(["password_hash", "!=", ""]);
  if (q.pw === "unset") f.push(["password_hash", "=", ""]);
  if (q.att === "yes") f.push(["attendance_count", ">", 0]);
  if (q.att === "no") f.push(["attendance_count", "=", 0]);
  if (q.from) f.push(["creation", ">=", `${q.from} 00:00:00`]);
  if (q.to) f.push(["creation", "<=", `${q.to} 23:59:59`]);
  return f;
}
/** Free-text search over name or mobile (OR-ed, so it is passed as ERPNext `or_filters`). */
export const searchFilters = (q: string) => (q ? [["full_name", "like", `%${q}%`], ["mob_no", "like", `%${q}%`]] : undefined);

/** The current query as URL params, minus empty values, with optional overrides (used by links and export). */
export function toParams(q: Partial<PeopleQuery>, over: Partial<PeopleQuery> = {}) {
  const merged = { ...q, ...over };
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(merged)) if (v !== "" && v !== undefined && !(k === "sort" && v === "newest") && !(k === "page" && v === 1)) u.set(k, String(v));
  return u.toString();
}
