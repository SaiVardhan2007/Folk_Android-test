// Dropdown lists stored by ID: College / Company, Branch, Skill, Interest, PG / Residence, Area of stay.
// Each value is a record in its own ERPNext DocType with a random ID that never changes and an editable Title.
// People store only the ID, so editing a Title in ERPNext changes it for everyone at once.

export const LISTS = { college: "FOLK College", branch: "FOLK Branch", skill: "FOLK Skill", interest: "FOLK Interest", pg: "FOLK PG", area: "FOLK Area" } as const;
export type ListName = keyof typeof LISTS;
export const LIST_NAMES = Object.keys(LISTS) as ListName[];

export type Opt = { id: string; title: string };
/** A FOLK Guide: the name (in capitals) and the guide's phone, kept on the guide, not on each person. Added in ERPNext only. */
export type Guide = Opt & { mobile: string; is_default: boolean };
export type Options = Record<ListName, Opt[]> & { guide: Guide[] };

/** Two titles are the same value when they differ only in case, spaces or punctuation ("C.B.I.T" = "Cbit" = "CBIT"). */
export const sameKey = (s: string) => s.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");

/** A title as it is saved: single spaces, trimmed, at most 100 characters. Skills and interests can't contain commas (commas separate them in text). */
export function tidyTitle(v: unknown, list: ListName): string {
  if (typeof v !== "string") return "";
  const s = list === "skill" || list === "interest" ? v.replace(/,/g, " ") : v;
  return s.replace(/\s+/g, " ").trim().slice(0, 100);
}

/** "Singing, Video Editing" -> ["Singing", "Video Editing"] (for apps and forms that send text). */
export const splitTitles = (v: unknown): string[] =>
  typeof v === "string" ? [...new Set(v.split(",").map((s) => s.replace(/\s+/g, " ").trim().slice(0, 100)).filter(Boolean))] : [];

export function findTitle(list: Opt[], title: string): Opt | undefined {
  const k = sameKey(title);
  return k ? list.find((o) => sameKey(o.title) === k) : undefined;
}

/** Child table rows for a multi-value field: skill_list -> FOLK User Skill.skill, interest_list -> FOLK User Interest.interest. */
export const MULTI = {
  skill: { field: "skill_list", child: "FOLK User Skill", link: "skill" },
  interest: { field: "interest_list", child: "FOLK User Interest", link: "interest" },
} as const;
