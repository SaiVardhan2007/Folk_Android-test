/**
 * Import of contacts from a Google Form's response sheet (or any CSV): reading, column mapping, cleaning.
 * Pure functions, no network except [loadSheetCsv]. The routes in index.ts decide what to save.
 */
import { GENDERS, LEVELS } from "./types";

export const MAX_IMPORT_ROWS = 3000;
export const MAX_IMPORT_BYTES = 2_000_000;

/** Contact fields an import can fill. `mob` and `name` are required. */
export const IMPORT_FIELDS = ["mob", "name", "level", "gender", "occupation", "profession", "pg_name", "venue", "gmap_link", "call_no", "fg_name", "fg_mob", "event_code"] as const;
export type ImportField = (typeof IMPORT_FIELDS)[number];
export type Mapping = Partial<Record<ImportField, number>>; // field -> column index

/** RFC 4180 CSV reader (quotes, escaped quotes, CRLF, BOM). */
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [], cell = "", q = false;
  const s = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (q) {
      if (ch === '"') { if (s[i + 1] === '"') { cell += '"'; i++; } else q = false; } else cell += ch;
    } else if (ch === '"') q = true;
    else if (ch === ",") { row.push(cell); cell = ""; }
    else if (ch === "\n" || ch === "\r") {
      if (ch === "\r" && s[i + 1] === "\n") i++;
      row.push(cell); cell = "";
      if (row.some((c) => c.trim() !== "")) rows.push(row);
      row = [];
    } else cell += ch;
  }
  row.push(cell);
  if (row.some((c) => c.trim() !== "")) rows.push(row);
  return rows;
}

/** Turns a normal Google Sheets link into its CSV export address. */
export function sheetCsvUrl(link: string): string | null {
  const m = /\/spreadsheets\/d\/([a-zA-Z0-9_-]+)/.exec(link) ?? /^([a-zA-Z0-9_-]{25,})$/.exec(link.trim());
  if (!m) return null;
  const gid = /[#&?]gid=(\d+)/.exec(link)?.[1] ?? "0";
  return `https://docs.google.com/spreadsheets/d/${m[1]}/export?format=csv&gid=${gid}`;
}

export class ImportError extends Error {}

export async function loadSheetCsv(link: string): Promise<string> {
  const url = sheetCsvUrl(link);
  if (!url) throw new ImportError("That does not look like a Google Sheets link.");
  const res = await fetch(url, { redirect: "follow", headers: { "User-Agent": "Mozilla/5.0 (FOLK Tracker)" } });
  const text = await res.text();
  if (!res.ok || /^\s*<(!doctype|html)/i.test(text)) {
    throw new ImportError("Could not read the sheet. In Google Sheets choose Share, then General access: Anyone with the link (Viewer), and try again.");
  }
  if (text.length > MAX_IMPORT_BYTES) throw new ImportError("The sheet is too large. Import it in smaller parts.");
  return text;
}

const HINTS: Record<ImportField, RegExp> = {
  mob: /(mobile|phone|contact|whats ?app|number|mob\b)/i,
  name: /(^name|full name|your name|student name|\bname\b)/i,
  level: /(level|course|batch)/i,
  gender: /(gender|sex)/i,
  occupation: /(occupation|status|studying|working)/i,
  profession: /(profession|company|college|organi[sz]ation|institute|work ?place|employer)/i,
  pg_name: /(pg|hostel|residence|stay|area|locality)/i,
  venue: /(venue|location|address|place)/i,
  gmap_link: /(g ?map|google map|map link|maps)/i,
  call_no: /(call (no|number)|helpline|call to)/i,
  fg_name: /(fg name|guide name|folk guide|guide)/i,
  fg_mob: /(fg (mob|phone|number)|guide (mob|phone|number))/i,
  event_code: /(event|session|programme|program)/i,
};

/** Suggests which column holds which field, from the header texts. Each column is used once; the most specific fields claim first. */
export function guessMapping(headers: string[]): Mapping {
  const order: ImportField[] = ["fg_mob", "fg_name", "gmap_link", "call_no", "mob", "name", "gender", "level", "occupation", "pg_name", "venue", "profession", "event_code"];
  const used = new Set<number>(), out: Mapping = {};
  for (const f of order) {
    const i = headers.findIndex((h, idx) => !used.has(idx) && HINTS[f].test(h));
    if (i >= 0) { out[f] = i; used.add(i); }
  }
  return out;
}

const norm = (s: string) => s.trim().replace(/\s+/g, " ");

export function cleanGender(v: string): "M" | "F" | "" {
  const s = v.trim().toLowerCase();
  if (/^(m|male|boy|man|prabhu)/.test(s)) return "M";
  if (/^(f|female|girl|woman|mataji)/.test(s)) return "F";
  return (GENDERS as readonly string[]).includes(v) ? (v as "M" | "F") : "";
}

export function cleanLevel(v: string, fallback: string): string {
  const s = v.toLowerCase();
  if (/prelim/.test(s)) return "Folk Prelims";
  if (/found/.test(s)) return "Folk Foundation";
  return (LEVELS as readonly string[]).includes(fallback) ? fallback : "Folk Foundation";
}

export function cleanOccupation(v: string): string {
  const s = v.toLowerCase();
  if (/student|study|college|school/.test(s)) return "Student";
  if (/search|seek|unemploy|fresher/.test(s)) return "Job Search";
  if (/work|job|employ|business|self/.test(s)) return "Working";
  return "";
}

export interface ImportRow {
  line: number; // line number in the sheet (header = 1)
  mob: string;
  name: string;
  level: string;
  gender: string;
  occupation: string;
  profession: string;
  pg_name: string;
  venue: string;
  gmap_link: string;
  call_no: string;
  fg_name: string;
  fg_mob: string;
  event_code: string;
}

export interface Built { rows: ImportRow[]; invalid: { line: number; reason: string; name: string; mob: string }[]; duplicatesInSheet: number }

/** Applies the column mapping to every data row. Bad rows are reported, never silently dropped. */
export function buildRows(
  table: string[][],
  map: Mapping,
  opts: { defaultLevel: string; normalizeMobile: (v: unknown) => string | null; knownEvent: (v: string) => string },
): Built {
  const rows: ImportRow[] = [], invalid: Built["invalid"] = [];
  const seen = new Set<string>();
  let duplicatesInSheet = 0;
  for (let r = 1; r < table.length; r++) {
    const cells = table[r];
    const get = (f: ImportField) => (map[f] === undefined ? "" : norm(cells[map[f]!] ?? ""));
    const mob = opts.normalizeMobile(get("mob"));
    const name = get("name");
    if (!mob) { invalid.push({ line: r + 1, reason: "Mobile number is not a valid 10-digit number", name, mob: get("mob") }); continue; }
    if (!name) { invalid.push({ line: r + 1, reason: "Name is empty", name, mob }); continue; }
    if (seen.has(mob)) { duplicatesInSheet++; continue; }
    seen.add(mob);
    rows.push({
      line: r + 1, mob, name: name.slice(0, 120),
      level: cleanLevel(get("level"), opts.defaultLevel), gender: cleanGender(get("gender")), occupation: cleanOccupation(get("occupation")),
      profession: get("profession").slice(0, 120), pg_name: get("pg_name").slice(0, 120), venue: get("venue").slice(0, 200), gmap_link: get("gmap_link").slice(0, 500),
      call_no: opts.normalizeMobile(get("call_no")) ?? "", fg_name: get("fg_name").slice(0, 120), fg_mob: opts.normalizeMobile(get("fg_mob")) ?? "",
      event_code: opts.knownEvent(get("event_code")),
    });
  }
  return { rows, invalid, duplicatesInSheet };
}
