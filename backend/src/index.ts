// FOLK Tracker API: a thin, fast layer between the Flutter app and ERPNext.
import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Context } from "hono";
import { Erp, ErpError, type Filters } from "./erp";
import { sha256Hex, randomCode, signToken, verifyToken } from "./crypto";
import { analytics } from "./analytics";
import { sendOtpSms } from "./sms";
import { attendanceAlert, defaultsOf, sendTemplate, welcomeMessage } from "./whatsapp";
import { pushTo, DEVICE } from "./push";
import { buildRows, guessMapping, IMPORT_FIELDS, ImportError, loadSheetCsv, MAX_IMPORT_BYTES, MAX_IMPORT_ROWS, parseCsv, type ImportField, type ImportRow, type Mapping } from "./importer";
import { notFoundPage, pageHeaders, renderPage, type PageConfig } from "./publicPage";
import { FOLLOW_UP, NOTE_REQUIRED, passes, PENDING, POSITIVE, shareOut, shuffle, STATUSES, type Attrs, type Member, type PoolFilter } from "./calls";
import { findTitle, LIST_NAMES, LISTS, MULTI, sameKey, splitTitles, tidyTitle, type Guide, type ListName, type Opt, type Options } from "./options";
import { CONTACT_TAGS, DEFAULT_TAGS, DONATIONS, NOT_INTERESTED, FEEDBACKS, GENDERS, LEVELS, OCCUPATIONS, STAYS, type Bindings, type Session, type Vars } from "./types";

type Ctx = Context<{ Bindings: Bindings; Variables: Vars }>;
const app = new Hono<{ Bindings: Bindings; Variables: Vars }>();

const TOKEN_TTL = 180 * 24 * 3600; // renewed each time the app opens, so active users are never signed out
const PERSON = "FOLK Users";
const ATT = "FOLK Attendance";
const GUIDE = "FOLK Guide";
const ASG = "FOLK Assignment";
const LOG = "FOLK Call Log";
const REG = "FOLK Registration";
const ACT = "FOLK Activity Log";
const LINK = "FOLK Form Link";
const FB = "FOLK Feedback";
const PAGE_SIZE = 25;

// ---------- small helpers
class HttpError extends Error {
  constructor(public status: number, message: string, public extra: Record<string, unknown> = {}) {
    super(message);
  }
}
const bad = (m: string, extra?: Record<string, unknown>) => new HttpError(400, m, extra);

/** 10-digit Indian mobile, or null. Strips +91 / 91 / leading 0 and any spaces or dashes. */
export function normalizeMobile(raw: unknown): string | null {
  let d = String(raw ?? "").replace(/\D/g, "");
  if (d.length === 12 && d.startsWith("91")) d = d.slice(2);
  if (d.length === 11 && d.startsWith("0")) d = d.slice(1);
  return /^\d{10}$/.test(d) ? d : null;
}
/** Drops empty values so an edit can never wipe saved details by accident. */
const nonEmpty = (o: Record<string, unknown>) => Object.fromEntries(Object.entries(o).filter(([, v]) => v !== "" && v !== undefined));
const clean = (v: unknown, max = 120) => (typeof v === "string" ? v.trim().slice(0, max) : "");
const pick = <T extends string>(v: unknown, allowed: readonly T[]): T | "" => (allowed as readonly string[]).includes(v as string) ? (v as T) : "";

/** Asia/Kolkata wall-clock time as "YYYY-MM-DD HH:mm:ss" (what ERPNext stores). */
const istNow = () => new Date(Date.now() + 5.5 * 3600_000).toISOString().replace("T", " ").slice(0, 19);
const istToday = () => istNow().slice(0, 10);
/** Monday and Sunday (YYYY-MM-DD) of the current India-time week. Weekly events (the Saturday Satsang) count calls inside this window. */
function istWeek() {
  const d = new Date(Date.now() + 5.5 * 3600_000);
  const sinceMonday = (d.getUTCDay() + 6) % 7;
  const day = (offset: number) => new Date(d.getTime() + offset * 86400_000).toISOString().slice(0, 10);
  return { from: day(-sinceMonday), to: day(6 - sinceMonday) };
}
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TS_RE = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/;
const addDays = (d: string, n: number) => new Date(new Date(d + "T00:00:00Z").getTime() + n * 86400_000).toISOString().slice(0, 10);

const isDuplicate = (e: unknown) => e instanceof ErpError && (e.status === 409 || /Duplicate|already exists/i.test(e.message));
const erpOf = (c: Ctx) => new Erp(c.env);

type Row = {
  name: string; mob_no: string; full_name: string; gender?: string; level?: string; occupation?: string; pg?: string | null; pg_title?: string | null; area?: string | null; area_title?: string | null; dob?: string | null;
  college?: string | null; college_title?: string | null; branch?: string | null; branch_title?: string | null;
  event_code?: string; user_tag?: string; is_active?: number; attendance_count?: number; last_attended_on?: string | null;
  registered_by?: string; reset_code_hash?: string; reset_code_expires?: string; reset_attempts?: number; creation?: string; registered_on?: string;
  venue?: string; guide?: string | null; guide_title?: string | null; guide_mobile?: string | null;
  age?: number; current_stay?: string; chanting_rounds?: number; feedback?: string; comments?: string;
};
// College / Company and Branch are stored as IDs; their titles are read through the link ("college.title"), so a title edited in ERPNext shows everywhere at once.
const PERSON_FIELDS = ["name", "mob_no", "full_name", "gender", "level", "occupation", "college", "college.title as college_title", "branch", "branch.title as branch_title", "pg", "pg.title as pg_title", "area", "area.title as area_title", "event_code", "user_tag", "is_active", "attendance_count", "last_attended_on", "registered_by", "creation", "venue", "guide", "guide.title as guide_title", "guide.mobile as guide_mobile", "registered_on", "age", "dob", "current_stay", "chanting_rounds", "feedback", "comments"];
const AUTH_FIELDS = [...PERSON_FIELDS, "reset_code_hash", "reset_code_expires", "reset_attempts"];

/** Skills and interests of a person (child tables), as {id, title}. */
type Multi = { skills: Opt[]; interests: Opt[] };
const NO_MULTI: Multi = { skills: [], interests: [] };

/**
 * What the app is allowed to see about a person. Never includes any hash.
 * Dropdown values are sent twice: by ID (college_id, branch_id, skill_list/interest_list as [{id, title}]; used by the app from 1.0.8)
 * and as text (profession, branch, skills, interests), which older app versions and every display use.
 */
const publicPerson = (r: Row, m: Multi = NO_MULTI) => ({
  id: r.name, mob: r.mob_no, name: r.full_name, gender: r.gender ?? "", level: r.level ?? "", occupation: r.occupation ?? "",
  profession: r.college_title ?? "", college_id: r.college ?? "", branch: r.branch_title ?? "", branch_id: r.branch ?? "",
  skills: m.skills.map((o) => o.title).join(", "), skill_list: m.skills,
  interests: m.interests.map((o) => o.title).join(", "), interest_list: m.interests,
  pg_name: r.pg_title ?? "", pg_id: r.pg ?? "", area_name: r.area_title ?? "", area_id: r.area ?? "", event_code: r.event_code ?? "", tag: r.user_tag || "Public",
  is_active: r.is_active !== 0, attendance_count: r.attendance_count ?? 0, last_attended_on: r.last_attended_on ?? "",
  registered_by: r.registered_by ?? "", joined: (r.registered_on || r.creation || "").slice(0, 10),
  venue: r.area_title ?? "", // the old typed area is retired; this name is what older apps read
  guide: (r.guide_title ?? "").toUpperCase(), guide_id: r.guide ?? "", guide_mobile: r.guide_mobile ?? "",
  // The FOLK guide used to be typed per person; app 1.0.7 still reads these names.
  folk_guide: (r.guide_title ?? "").toUpperCase(), fg_name: (r.guide_title ?? "").toUpperCase(), fg_mob: r.guide_mobile ?? "", call_no: "",
  // Age is worked out from the date of birth; people entered before dates of birth were asked keep the age typed back then.
  dob: r.dob ?? "", age: ageOn(r.dob, istToday()) ?? r.age ?? 0, current_stay: r.current_stay ?? "", chanting_rounds: r.chanting_rounds ?? 0,
  feedback: r.feedback ?? "", comments: r.comments ?? "",
});

// ---------- tiny in-isolate caches (each Cloudflare isolate keeps its own; they only absorb bursts)
const memo = new Map<string, { at: number; v: unknown }>();
async function cached<T>(key: string, ttlMs: number, load: () => Promise<T>): Promise<T> {
  const hit = memo.get(key);
  if (hit && Date.now() - hit.at < ttlMs) return hit.v as T;
  const v = await load();
  memo.set(key, { at: Date.now(), v });
  if (memo.size > 500) memo.delete(memo.keys().next().value as string);
  return v;
}

// ---------- errors
app.onError((e, c) => {
  if (e instanceof HttpError) return c.json({ error: e.message, ...e.extra }, e.status as 400);
  if (e instanceof ErpError) {
    console.error("ERPNext error", e.status, e.message);
    return c.json({ error: "The server is busy. Please try again." }, 502);
  }
  console.error(e);
  return c.json({ error: "Something went wrong." }, 500);
});
app.notFound((c) => c.json({ error: "Not found" }, 404));
app.get("/", (c) => c.json({ ok: true, service: "folk-api" }));
app.get("/health", (c) => c.json({ ok: true, time: istNow() }));

// ---------- activity log: one record per change anyone makes (user, coordinator or admin). Reads are not logged.
type Body = Record<string, unknown>;
const str = (v: unknown) => (typeof v === "string" || typeof v === "number" ? String(v).slice(0, 120) : "");
/** [method, path pattern, what it is called in the log, optional safe detail]. Passwords, codes and keys are never recorded. */
const ACTIVITY: [string, RegExp, string, ((b: Body, path: string) => string)?][] = [
  ["POST", /^\/auth\/otp\/verify$/, "Signed in with an SMS code"],
  ["POST", /^\/auth\/signup$/, "Signed up", (b) => str(b.name)],
  ["POST", /^\/people$/, "Registered a contact", (b) => str(b.name)],
  ["PUT", /^\/people\/\d+$/, "Edited a contact"],
  ["PUT", /^\/admin\/people\/\d+$/, "Edited a person's details"],
  ["POST", /^\/attendance$/, "Marked attendance", (b) => `event ${str(b.event)}`],
  ["DELETE", /^\/attendance\//, "Removed an attendance record"],
  ["POST", /^\/registrations$/, "Registered a person for an event", (b) => `event ${str(b.event)}`],
  ["POST", /^\/my\/calls\/[^/]+\/submit$/, "Logged a call", (b) => str(b.status)],
  ["POST", /^\/pub\/[^/]+\/submit$/, "Submitted a public form"],
  ["POST", /^\/admin\/links$/, "Created a registration link", (b) => str(b.title)],
  ["PATCH", /^\/admin\/links\/[^/]+$/, "Changed a registration link", (b) => str(b.title)],
  ["PATCH", /^\/admin\/people\/\d+\/role$/, "Changed a role", (b) => str(b.tag)],
  ["PATCH", /^\/admin\/people\/\d+\/active$/, "Enabled or disabled an account", (b) => (b.active ? "enabled" : "disabled")],
  ["POST", /^\/admin\/events$/, "Added an event", (b) => str(b.name)],
  ["POST", /^\/admin\/events\/[^/]+\/current$/, "Changed the current event", (_b, path) => `now ${decodeURIComponent(path.split("/")[3] ?? "")}`],
  ["PUT", /^\/admin\/settings$/, "Changed settings", (b) => Object.keys(b).slice(0, 8).join(", ")],
  ["POST", /^\/admin\/assign\/finish$/, "Assigned calls", (b) => `${str(b.scope)}: ${Number(b.assigned) || 0} contact(s), event ${str(b.event)}`],
  ["POST", /^\/admin\/assign\/unassign$/, "Removed unstarted call assignments", (b) => `event ${str(b.event)}`],
  ["PATCH", /^\/admin\/callers\/\d+$/, "Changed a caller's call settings"],
  ["POST", /^\/admin\/import\/commit$/, "Imported contacts"],
  ["PUT", /^\/admin\/import\/sources$/, "Changed import sources"],
  ["PUT", /^\/admin\/templates$/, "Changed WhatsApp templates"],
];

async function activityLog(c: Ctx, next: () => Promise<void>) {
  await next();
  const m = c.req.method;
  if (m === "GET" || m === "HEAD" || m === "OPTIONS" || c.res.status >= 400) return;
  const rule = ACTIVITY.find(([method, re]) => method === m && re.test(c.req.path));
  if (!rule) return;
  try {
    let b: Body = {};
    if (rule[3]) { try { b = (await c.req.json()) as Body; } catch { /* no body */ } }
    const who = c.get("actor") ?? c.get("session");
    const extra = c.get("log");
    const mob = /\/(\d{10})(\/|$)/.exec(c.req.path)?.[1] ?? normalizeMobile(b.mob) ?? "";
    const doc = {
      at: istNow(), user_id: who?.id ?? "", user_name: who?.name ?? str(b.name) ?? "", role: who?.tag ?? "Not signed in",
      action: rule[2], target: extra?.target ?? mob, details: extra?.details ?? rule[3]?.(b, c.req.path) ?? "",
    };
    c.executionCtx.waitUntil(erpOf(c).insert(ACT, doc).catch((e) => console.error("activity log", e)));
  } catch (e) { console.error("activity log", e); }
}
// The website calls this API from the browser. Bearer tokens only, no cookies, so no credentials mode.
// Allowed: the real domain, the Cloudflare Pages address and its per-deploy previews, and local `flutter run -d chrome`.
const WEB_ORIGINS = ["https://folk.hkmh.in", "https://folk-web.pages.dev"];
const WEB_ORIGIN_PATTERNS = [/^https:\/\/[a-z0-9-]+\.folk-web\.pages\.dev$/, /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/];
const webOrigin = (o: string) => (WEB_ORIGINS.includes(o) || WEB_ORIGIN_PATTERNS.some((r) => r.test(o)) ? o : null);
app.use("*", cors({ origin: webOrigin, allowMethods: ["GET", "POST", "PUT", "PATCH", "DELETE"], allowHeaders: ["Authorization", "Content-Type"], maxAge: 86400 }));
app.use("*", activityLog);

// ---------- admin-controlled settings (FOLK Settings, a single record)
/**
 * What is printed on the attendance receipt. Edited in Admin → Settings, used by every phone.
 * `text` is the receipt typed freely by the admin, with fields such as {name} and {phone} (the app fills them in). While `text` is empty the phones
 * build the layout from the older title / subtitle / footer / show_* values, so a receipt saved before this change looks the same.
 */
type ReceiptFormat = { text: string; show_logo: boolean; title: string; subtitle: string; footer: string; show_event: boolean; show_phone: boolean; show_time: boolean; show_count: boolean; show_marked_by: boolean };
const RECEIPT_DEFAULT: ReceiptFormat = { text: "", show_logo: true, title: "FOLK", subtitle: "Attendance Receipt", footer: "Hare Krishna!", show_event: true, show_phone: true, show_time: true, show_count: true, show_marked_by: false };
const RECEIPT_FLAGS = ["show_logo", "show_event", "show_phone", "show_time", "show_count", "show_marked_by"] as const;
const RECEIPT_TEXT_MAX = 800, RECEIPT_LINES_MAX = 30;
const RECEIPT_TEXTS = ["title", "subtitle", "footer"] as const;
function receiptFrom(raw: unknown): ReceiptFormat {
  let o: Record<string, unknown> = {};
  try { const v = typeof raw === "string" && raw ? JSON.parse(raw) : raw; if (v && typeof v === "object") o = v as Record<string, unknown>; } catch { /* use defaults */ }
  const out = { ...RECEIPT_DEFAULT };
  for (const k of RECEIPT_TEXTS) if (typeof o[k] === "string") out[k] = (o[k] as string).trim().slice(0, 60);
  if (typeof o.text === "string") out.text = o.text.split(/\r?\n/).slice(0, RECEIPT_LINES_MAX).map((l) => l.trimEnd()).join("\n").trim().slice(0, RECEIPT_TEXT_MAX);
  for (const k of RECEIPT_FLAGS) if (typeof o[k] === "boolean") out[k] = o[k] as boolean;
  return out;
}

/** App update notice. A phone whose build number is below `min_build` must update (cannot dismiss); below `latest_build` it is asked, once per launch. */
type AppUpdate = { latest_build: number; min_build: number; url: string; message: string };
const UPDATE_DEFAULT: AppUpdate = { latest_build: 0, min_build: 0, url: "", message: "" };
function updateFrom(raw: unknown): AppUpdate {
  let o: Record<string, unknown> = {};
  try { const v = typeof raw === "string" && raw ? JSON.parse(raw) : raw; if (v && typeof v === "object") o = v as Record<string, unknown>; } catch { /* defaults */ }
  const n = (v: unknown) => (Number.isInteger(v) && (v as number) >= 0 && (v as number) < 1_000_000 ? (v as number) : 0);
  const url = typeof o.url === "string" && /^https:\/\//.test(o.url.trim()) ? o.url.trim().slice(0, 500) : "";
  return { latest_build: n(o.latest_build), min_build: n(o.min_build), url, message: typeof o.message === "string" ? o.message.trim().slice(0, 300) : "" };
}

type Settings = { app_update: AppUpdate; offline_queue_enabled: boolean; auto_approve_signups: boolean; whatsapp_enabled: boolean; notify_coordinator_attendance: boolean; welcome_template: string; attendance_template: string; current_event: string; receipt: ReceiptFormat };
const loadSettings = (c: Ctx): Promise<Settings> =>
  cached("settings", 15_000, async () => {
    const r = (await erpOf(c).get<Record<string, unknown>>("FOLK Settings", "FOLK Settings")) ?? {};
    return {
      app_update: updateFrom(r.app_update),
      offline_queue_enabled: !!r.offline_queue_enabled, auto_approve_signups: !!r.auto_approve_signups,
      whatsapp_enabled: !!r.whatsapp_enabled, notify_coordinator_attendance: !!r.notify_coordinator_attendance,
      welcome_template: String(r.welcome_template || "event_registration"), attendance_template: String(r.attendance_template || "coordinator_attendance"),
      current_event: String(r.current_event ?? ""),
      receipt: receiptFrom(r.receipt_format),
    };
  });

// ---------- auth
async function rateLimit(c: Ctx) {
  const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
  const r = await c.env.AUTH_LIMITER?.limit({ key: ip });
  if (r && !r.success) throw new HttpError(429, "Too many attempts. Please wait a minute and try again.");
}
/** A session lasts TOKEN_TTL and is renewed whenever the app opens (/me), so people who use the app stay signed in.
 *  Access ends at once when an admin disables the account or makes it Public (checked on every request). */
async function issue(c: Ctx, r: Row) {
  const token = await signToken({ sub: r.name }, c.env.JWT_SECRET, TOKEN_TTL);
  return { token, user: publicPerson(r) };
}

/** Find a person by mobile number (the ID is generated, so the number is looked up through its unique index). */
async function getRow(erp: Erp, mob: string): Promise<Row | null> {
  const rows = await erp.list<Row>(PERSON, AUTH_FIELDS, [["mob_no", "=", mob]], { limit_page_length: 1 });
  return rows[0] ?? null;
}
/** By ID. A list query (not a document read) so the dropdown titles come with it. */
async function getById(erp: Erp, id: string): Promise<Row | null> {
  const rows = await erp.list<Row>(PERSON, AUTH_FIELDS, [["name", "=", id]], { limit_page_length: 1 });
  return rows[0] ?? null;
}
/** Every role except the contact roles (Public, Not Interested) can use the app: Coordinator, Admin, and any role an admin adds. */
const isStaffRow = (r: Row) => !CONTACT_TAGS.includes(r.user_tag || "Public");

async function body(c: Ctx): Promise<Record<string, unknown>> {
  try { return (await c.req.json()) as Record<string, unknown>; } catch { throw bad("Invalid request."); }
}

function details(b: Record<string, unknown>) {
  return {
    gender: pick(b.gender, GENDERS), level: pick(b.level, LEVELS), occupation: pick(b.occupation, OCCUPATIONS),
    dob: dateOfBirth(b.dob),
    // Numbers and flags are only included when sent, so an edit that leaves them out can never reset them.
    age: intIn(b.age, 1, 120), chanting_rounds: intIn(b.chanting_rounds, 0, 1000),
    current_stay: pick(b.current_stay, STAYS), feedback: pick(b.feedback, FEEDBACKS),
    comments: clean(b.comments, 500),
  };
}

// ---------- dropdown lists stored by ID (College / Company, Branch, Skill, Interest)
async function loadOptions(c: Ctx): Promise<Options> {
  return cached("options", 60_000, async () => {
    const erp = erpOf(c);
    const [all, guides] = await Promise.all([
      Promise.all(LIST_NAMES.map((l) => erp.list<{ name: string; title: string }>(LISTS[l], ["name", "title"], [], { order_by: "title asc" }))),
      erp.list<{ name: string; title: string; mobile?: string; is_default?: number }>(GUIDE, ["name", "title", "mobile", "is_default"], [], { order_by: "title asc" }),
    ]);
    const lists = Object.fromEntries(LIST_NAMES.map((l, i) => [l, all[i].map((r) => ({ id: r.name, title: r.title }))])) as Record<ListName, Opt[]>;
    return { ...lists, guide: guides.map((g): Guide => ({ id: g.name, title: g.title.toUpperCase(), mobile: g.mobile ?? "", is_default: !!g.is_default })) };
  });
}
const freshOptions = (c: Ctx) => { memo.delete("options"); return loadOptions(c); };

/**
 * The ID for a typed value: an existing value that differs only in case, spaces or punctuation is reused, otherwise it is added.
 * "" for an empty value. Safe when two people add the same value at once (Title is unique in ERPNext).
 */
async function optionId(c: Ctx, list: ListName, raw: unknown): Promise<string> {
  const title = tidyTitle(raw, list);
  if (!sameKey(title)) return "";
  const hit = findTitle((await loadOptions(c))[list], title) ?? findTitle((await freshOptions(c))[list], title);
  if (hit) return hit.id;
  try {
    const r = await erpOf(c).insert<{ name: string }>(LISTS[list], { title });
    memo.delete("options");
    return r.data.name;
  } catch (e) {
    if (!isDuplicate(e)) throw e;
    const again = findTitle((await freshOptions(c))[list], title); // someone added it a moment ago
    if (again) return again.id;
    throw e;
  }
}

/**
 * FOLK Guide from a request: an ID from the list (app 1.0.8+), or a name that is already in the list (older apps, imports).
 * Guides are added only in ERPNext, so an unknown name is ignored. New people get the default guide from ERPNext.
 */
async function guideField(c: Ctx, b: Record<string, unknown>): Promise<Record<string, unknown>> {
  const guides = (await loadOptions(c)).guide;
  if (typeof b.guide_id === "string" && b.guide_id) {
    if (!guides.some((g) => g.id === b.guide_id)) throw bad("That FOLK guide was removed from the list. Please pick again.");
    return { guide: b.guide_id };
  }
  const named = typeof b.folk_guide === "string" ? b.folk_guide : typeof b.fg_name === "string" ? b.fg_name : "";
  const hit = named ? findTitle(guides, named) : undefined;
  return hit ? { guide: hit.id } : {};
}
const guideOf = async (c: Ctx, id: string | null | undefined): Promise<Guide | undefined> => (id ? (await loadOptions(c)).guide.find((g) => g.id === id) : undefined);

/** The value people pick on the public form when their college / company is not in the list. */
const OTHERS = "Others";

/**
 * College / Company from the public form. People there can only pick an existing value or "Others" (they never add values;
 * only app users can). A name typed on an older copy of the page is used only when it is already in the list, else "Others".
 */
async function publicCollege(c: Ctx, b: Record<string, unknown>): Promise<string> {
  const id = clean(b.college_id, 40);
  if (id && id !== "other") return knownId(c, "college", id);
  const typed = tidyTitle(b.profession, "college");
  if (!id && !sameKey(typed)) return "";
  const hit = typed ? findTitle((await loadOptions(c)).college, typed) : undefined;
  return hit ? hit.id : optionId(c, "college", OTHERS);
}

/** Area of stay from the public form: an existing area or "Others" (never a new value), like the college. */
async function publicArea(c: Ctx, b: Record<string, unknown>): Promise<string> {
  const id = clean(b.area_id, 40);
  if (!id) return "";
  if (id === "other") return optionId(c, "area", OTHERS);
  return knownId(c, "area", id);
}

/** An ID sent by the app must exist in that list. */
async function knownId(c: Ctx, list: ListName, raw: unknown): Promise<string> {
  const id = clean(raw, 40);
  if (!id) return "";
  const has = (o: Options) => o[list].some((x) => x.id === id);
  if (has(await loadOptions(c)) || has(await freshOptions(c))) return id;
  throw bad("A value you picked was removed from the list. Please pick it again.");
}

/**
 * The dropdown fields of a person from a request. The app sends IDs (college_id, branch_id, skill_ids, interest_ids);
 * older app versions, the public form and imports send text (profession, branch, skills, interests), which is matched or added.
 * A field that is not sent is left out (never changed). An empty value clears the field only when `clear` is true.
 */
async function listFields(c: Ctx, b: Record<string, unknown>, clear: boolean): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = {};
  const one = async (field: "college" | "branch" | "pg" | "area", idKey: string, textKey: string) => {
    const id = typeof b[idKey] === "string" ? await knownId(c, field, b[idKey]) : typeof b[textKey] === "string" ? await optionId(c, field, b[textKey]) : undefined;
    if (id === undefined || (!id && !clear)) return;
    out[field] = id || null;
  };
  const many = async (list: "skill" | "interest", idKey: string, textKey: string) => {
    let ids: string[] | undefined;
    if (Array.isArray(b[idKey])) ids = await Promise.all((b[idKey] as unknown[]).slice(0, 30).map((v) => knownId(c, list, v)));
    else if (typeof b[textKey] === "string") ids = await Promise.all(splitTitles(b[textKey]).slice(0, 30).map((t) => optionId(c, list, t)));
    if (ids === undefined) return;
    const unique = [...new Set(ids.filter(Boolean))];
    if (!unique.length && !clear) return;
    out[MULTI[list].field] = unique.map((id) => ({ [MULTI[list].link]: id }));
  };
  await Promise.all([one("college", "college_id", "profession"), one("branch", "branch_id", "branch"), one("pg", "pg_id", "pg_name"), one("area", "area_id", "area_name"), many("skill", "skill_ids", "skills"), many("interest", "interest_ids", "interests")]);
  return { ...out, ...(await guideField(c, b)) };
}

/** Skills and interests for these people, read from the child tables in one query each. */
async function loadMulti(erp: Erp, ids: string[]): Promise<Map<string, Multi>> {
  const out = new Map<string, Multi>();
  if (!ids.length) return out;
  const rows = (list: "skill" | "interest") => {
    const { child, link } = MULTI[list];
    const fields = ["parent", `${link} as id`, `${link}.title as title`];
    const q = (f: Filters) => erp.list<{ parent: string; id: string; title: string }>(child, fields, f, { parent: PERSON, order_by: "idx asc" });
    // Many people (an export): one query for everybody is cheaper than many "parent in (...)" queries.
    return ids.length > 300 ? q([["parenttype", "=", PERSON]]) : Promise.all(chunk(ids, 100).map((ch) => q([["parent", "in", ch]]))).then((r) => r.flat());
  };
  const [skills, interests] = await Promise.all([rows("skill"), rows("interest")]);
  const of = (id: string) => out.get(id) ?? out.set(id, { skills: [], interests: [] }).get(id)!;
  for (const r of skills) of(r.parent).skills.push({ id: r.id, title: r.title });
  for (const r of interests) of(r.parent).interests.push({ id: r.id, title: r.title });
  return out;
}
/** People as the app sees them, with their skills and interests. */
async function present(erp: Erp, rows: Row[]) {
  const m = await loadMulti(erp, rows.map((r) => r.name));
  return rows.map((r) => publicPerson(r, m.get(r.name)));
}
/** A whole number inside [min, max], or undefined (so the field is left alone). */
/** A date of birth "YYYY-MM-DD" between 1900 and today, else undefined (not sent / not valid). */
function dateOfBirth(v: unknown): string | undefined {
  if (typeof v !== "string" || !DATE_RE.test(v)) return undefined;
  return v >= "1900-01-01" && v <= istToday() ? v : undefined;
}
/** Whole years from [dob] to [today] (both "YYYY-MM-DD"). */
function ageOn(dob: string | null | undefined, today: string): number | undefined {
  if (!dob || !DATE_RE.test(dob)) return undefined;
  const y = Number(today.slice(0, 4)) - Number(dob.slice(0, 4));
  return today.slice(5) < dob.slice(5) ? y - 1 : y;
}

function intIn(v: unknown, min: number, max: number): number | undefined {
  if (v === null || v === "" || v === undefined) return undefined;
  const n = Math.floor(Number(v));
  return Number.isFinite(n) && n >= min && n <= max ? n : undefined;
}

/** Asks for a Coordinator account. There is no password: once approved (or at once, if sign-ups are auto-approved) the person signs in with an SMS code. */
app.post("/auth/signup", async (c) => {
  await rateLimit(c);
  const b = await body(c);
  const mob = normalizeMobile(b.mob);
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const name = clean(b.name);
  const erp = erpOf(c);
  const existing = await getRow(erp, mob);
  if (existing && isStaffRow(existing)) throw new HttpError(409, "This number already has an account. Sign in with an SMS code.", { has_account: true });
  const approved = (await loadSettings(c)).auto_approve_signups;
  const reply = () => c.json({ approved, message: approved ? "Your account is ready. We are sending you a code to sign in." : "Your account is created. An admin needs to approve it, then you can sign in with your mobile number." }, 201);
  if (existing) {
    // Claiming a number a volunteer registered as a contact: it becomes a Coordinator.
    await erp.update(PERSON, existing.name, { user_tag: "Coordinator", is_active: approved ? 1 : 0, ...(existing.registered_by ? {} : { registered_by: "self sign-up" }) });
    memo.delete(`p:${existing.name}`);
    return reply();
  }
  if (!name) throw bad("Enter your name.");
  const doc = { mob_no: mob, full_name: name, ...details(b), ...(await listFields(c, b, false)), user_tag: "Coordinator", is_active: approved ? 1 : 0, registered_by: "self sign-up", registered_on: istToday() };
  try {
    await erp.insert<Row>(PERSON, doc);
  } catch (e) {
    if (isDuplicate(e)) throw new HttpError(409, "This number is already registered. Sign in with an SMS code.", { has_account: true });
    throw e;
  }
  return reply();
});

// ---------- sign in by SMS code (OTP). No passwords.
// 1) /auth/otp/send: a random 6-digit code is texted to the number; only its hash is kept (reset_code_hash, 10 minutes).
// 2) /auth/otp/verify: the right code (max 5 tries per code) signs the person in. The code is then used up.
const OTP_MINUTES = 10;
const OTP_MAX_TRIES = 5;
const OTP_RESEND_SECONDS = 30;
const erpTime = (ms: number) => new Date(ms + 5.5 * 3600_000).toISOString().replace("T", " ").slice(0, 19);
const erpMs = (t: string) => Date.parse(t.replace(" ", "T") + "Z") - 5.5 * 3600_000;
/** The 11-character app hash Android needs at the end of the SMS to read it without asking (SMS Retriever API). */
const APP_HASH_RE = /^[A-Za-z0-9+/]{11}$/;

/** Only active Coordinators and Admins can sign in. Throws a clear message otherwise. */
function checkCanSignIn(r: Row | null) {
  if (!r || !isStaffRow(r)) throw new HttpError(404, "This number does not have a coordinator account. Tap “Sign up” to ask for an account.", { no_account: true });
  if (r.is_active === 0) throw new HttpError(403, "Your account is waiting for admin approval, or has been disabled.", { pending: true });
}

app.post("/auth/otp/send", async (c) => {
  await rateLimit(c);
  const b = await body(c);
  const mob = normalizeMobile(b.mob);
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const erp = erpOf(c);
  const r = await getRow(erp, mob);
  checkCanSignIn(r);
  // auto_read: the SMS template ends with the app hash, so the app can read the code with no "Allow" prompt.
  const reply = { ok: true, expires_in_minutes: OTP_MINUTES, resend_after_seconds: OTP_RESEND_SECONDS, auto_read: c.env.OTP_SMS_HAS_APP_HASH === "1" };
  const sentAt = r!.reset_code_expires ? erpMs(r!.reset_code_expires) - OTP_MINUTES * 60_000 : 0;
  if (Date.now() - sentAt < OTP_RESEND_SECONDS * 1000) return c.json(reply); // the last code was sent moments ago and is still valid
  const otp = randomCode();
  await erp.update(PERSON, r!.name, { reset_code_hash: await sha256Hex(`${mob}:${otp}`), reset_code_expires: erpTime(Date.now() + OTP_MINUTES * 60_000), reset_attempts: 0 });
  const hash = typeof b.app_hash === "string" && APP_HASH_RE.test(b.app_hash) ? b.app_hash : "";
  if (!(await sendOtpSms(c.env, mob, otp, hash))) {
    await erp.update(PERSON, r!.name, { reset_code_hash: "", reset_code_expires: null }); // so "send again" is not blocked
    throw new HttpError(502, "We could not send the SMS right now. Please try again in a minute.");
  }
  return c.json(reply);
});

app.post("/auth/otp/verify", async (c) => {
  await rateLimit(c);
  const b = await body(c);
  const mob = normalizeMobile(b.mob);
  const otp = clean(b.otp, 12);
  const erp = erpOf(c);
  const r = mob ? await getRow(erp, mob) : null;
  const wrong = new HttpError(400, "That code is wrong or has expired. Check the SMS or ask for a new code.");
  if (!r || !otp || !r.reset_code_hash || !r.reset_code_expires || erpMs(r.reset_code_expires) < Date.now()) throw wrong;
  if ((r.reset_attempts ?? 0) >= OTP_MAX_TRIES) throw new HttpError(429, "Too many wrong codes. Ask for a new code.");
  if ((await sha256Hex(`${mob}:${otp}`)) !== r.reset_code_hash) {
    await erp.update(PERSON, r.name, { reset_attempts: (r.reset_attempts ?? 0) + 1 });
    throw wrong;
  }
  await erp.update(PERSON, r.name, { reset_code_hash: "", reset_code_expires: null, reset_attempts: 0 }); // single use
  checkCanSignIn(r);
  c.set("actor", { id: r.name, mob: r.mob_no, name: r.full_name, tag: r.user_tag || "Public" });
  return c.json(await issue(c, r));
});

// ---------- session middleware for everything below
async function requireSession(c: Ctx, next: () => Promise<void>) {
  const h = c.req.header("Authorization") ?? "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  const payload = token ? await verifyToken(token, c.env.JWT_SECRET) : null;
  if (!payload || typeof payload.sub !== "string" || payload.purpose) throw new HttpError(401, "Please sign in again.", { signed_out: true });
  const id = payload.sub;
  // Role and active status are re-read (cached 60 s) so changes apply almost immediately.
  const valid = (r: Row | null) => !!r && r.is_active !== 0 && isStaffRow(r);
  let row = await cached(`p:${id}`, 60_000, () => getById(erpOf(c), id));
  if (!valid(row)) {
    // The cached copy may be stale (e.g. just approved on another instance): check the live record before rejecting.
    memo.delete(`p:${id}`);
    row = await cached(`p:${id}`, 60_000, () => getById(erpOf(c), id));
    if (!valid(row)) throw new HttpError(401, "Please sign in again.", { signed_out: true });
  }
  c.set("session", { id, mob: row!.mob_no, name: row!.full_name, tag: row!.user_tag || "Public" } satisfies Session);
  await next();
}
const isAdmin = (s: Session) => s.tag === "Admin";
const isStaff = (s: Session) => s.tag === "Admin" || s.tag === "Coordinator";
const needAdmin = (c: Ctx) => { if (!isAdmin(c.get("session"))) throw new HttpError(403, "Admin access required."); };
const needStaff = (c: Ctx) => { if (!isStaff(c.get("session"))) throw new HttpError(403, "Not allowed."); };

for (const p of ["/me", "/bootstrap", "/options", "/options/*", "/events", "/home", "/people", "/people/*", "/attendance", "/attendance/*", "/my/*", "/calls/*", "/devices", "/devices/*", "/print/jobs", "/print/status", "/registrations", "/admin/*", "/reports/*"]) app.use(p, requireSession);

// ---------- app update notice (public: a phone must learn it is out of date even before sign-in)
/** Phones are given OUR address for the APK (not the host's own link), so the Update button never opens another app such as GitHub's, which asks to sign in. */
app.get("/app/update", async (c) => {
  const u = (await loadSettings(c)).app_update;
  return c.json({ update: { ...u, url: u.url ? `${new URL(c.req.url).origin}/app/download` : "" } });
});

/** Streams the current APK (the link an admin saved under App update) through this Worker. Public: updating must work before sign-in. */
app.get("/app/download", async (c) => {
  await publicLimit(c);
  const u = (await loadSettings(c)).app_update;
  if (!u.url) throw new HttpError(404, "There is no update to download.");
  const res = await fetch(u.url, { redirect: "follow", headers: { "User-Agent": "folk-api/1.0" } });
  if (!res.ok || !res.body) throw new HttpError(502, "The update file is not available right now. Please try again later.");
  if ((res.headers.get("Content-Type") ?? "").includes("text/html")) throw new HttpError(502, "The saved download link opens a web page, not the app file. Ask an admin to save a direct .apk link.");
  const h = new Headers({ "Content-Type": "application/vnd.android.package-archive", "Content-Disposition": 'attachment; filename="FOLK-Tracker.apk"', "Cache-Control": "no-store" });
  const len = res.headers.get("Content-Length");
  if (len) h.set("Content-Length", len);
  return new Response(res.body, { status: 200, headers: h });
});

// ---------- app start-up
type EventRow = { name: string; event_name: string; is_current?: number; is_list?: number; is_weekly?: number };
/** Every FOLK Event row. `is_list` marks an always-open contact list (Feedback, Contacts Register) as opposed to a dated event. */
const loadEvents = (c: Ctx) =>
  cached("events", 30_000, async () =>
    (await erpOf(c).list<EventRow>("FOLK Event", ["name", "event_name", "is_current", "is_list", "is_weekly"], [], { order_by: "creation asc" }))
      .map((e) => ({ code: e.name, name: e.event_name, is_current: !!e.is_current && !e.is_list, is_list: !!e.is_list, weekly: !!e.is_weekly })));
/** Events and contact lists, kept apart for the app. */
const splitEvents = <T extends { is_list: boolean }>(all: T[]) => ({ events: all.filter((e) => !e.is_list), lists: all.filter((e) => e.is_list) });

async function tagOptions(c: Ctx): Promise<string[]> {
  return cached("tags", 300_000, async () => {
    try {
      const r = await erpOf(c).call("GET", "/api/resource/DocType/FOLK%20Users");
      const f = (r.data.fields as { fieldname: string; options?: string }[]).find((x) => x.fieldname === "user_tag");
      const opts = (f?.options ?? "").split("\n").map((o) => o.trim()).filter(Boolean);
      return opts.length ? opts : DEFAULT_TAGS;
    } catch { return DEFAULT_TAGS; }
  });
}

/** Who I am, plus a renewed session token (so a phone that keeps using the app stays signed in for good). */
app.get("/me", async (c) => {
  const r = await getById(erpOf(c), c.get("session").id);
  return c.json(r ? await issue(c, r) : { user: null });
});

/** One call at app start: who I am, the events, and the allowed values for forms. */
app.get("/bootstrap", async (c) => {
  const s = c.get("session");
  const [all, tags, r, settings] = await Promise.all([loadEvents(c), tagOptions(c), getById(erpOf(c), s.id), loadSettings(c)]);
  const { events, lists } = splitEvents(all);
  return c.json({
    user: r ? publicPerson(r) : null, events, lists, current_event: events.find((e) => e.is_current)?.code ?? events[0]?.code ?? "",
    tags, levels: LEVELS, genders: GENDERS, occupations: OCCUPATIONS, stays: STAYS, feedbacks: FEEDBACKS, today: istToday(),
    settings: { offline_queue_enabled: settings.offline_queue_enabled, receipt: settings.receipt },
  });
});
app.get("/events", async (c) => c.json(splitEvents(await loadEvents(c))));

/** Every dropdown list ({college, branch, skill, interest}: [{id, title}]) for the person forms. */
app.get("/options", async (c) => {
  needStaff(c);
  return c.json(await loadOptions(c));
});
/** The small "Add" next to a dropdown: adds a value (or returns the existing one if it differs only in case/spacing). */
app.post("/options/:list", async (c) => {
  needStaff(c);
  const list = pick(c.req.param("list"), LIST_NAMES);
  if (!list) throw new HttpError(404, "Unknown list.");
  const id = await optionId(c, list, (await body(c)).title);
  if (!id) throw bad("Type a value first.");
  const o = (await loadOptions(c))[list].find((x) => x.id === id);
  return c.json({ id, title: o?.title ?? "" }, 201);
});

app.get("/home", async (c) => {
  const event = clean(c.req.query("event"), 60);
  if (!event) throw bad("event is required");
  const date = istToday();
  const data = await cached(`home:${event}:${date}`, 5_000, async () => {
    return { registered: await erpOf(c).count(PERSON, [["event_code", "=", event]]) };
  });
  return c.json({ ...data, date });
});

// ---------- people
app.get("/people/search", async (c) => {
  const q = clean(c.req.query("q"), 60);
  if (q.length < 3) return c.json({ people: [] });
  const erp = erpOf(c);
  const digits = q.replace(/\D/g, "");
  const numeric = /^[\d\s+\-]+$/.test(q);
  const filters: Filters = numeric ? [["mob_no", "like", `${digits.slice(-10)}%`]] : [["full_name", "like", `%${q.replace(/[%_]/g, "")}%`]];
  const rows = await erp.list<Row>(PERSON, PERSON_FIELDS, filters, { limit_page_length: 8, order_by: "full_name asc" });
  return c.json({ people: await present(erp, rows) });
});

app.get("/people/:mob", async (c) => {
  const mob = normalizeMobile(c.req.param("mob"));
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const erp = erpOf(c);
  const r = await getRow(erp, mob);
  return c.json({ person: r ? (await present(erp, [r]))[0] : null });
});

app.post("/people", async (c) => {
  const b = await body(c);
  const s = c.get("session");
  const mob = normalizeMobile(b.mob);
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const name = clean(b.name);
  if (!name) throw bad("Enter the name.");
  const d = details(b);
  if (!d.level) throw bad("Choose a level.");
  const doc = { mob_no: mob, full_name: name, ...d, ...(await listFields(c, b, false)), event_code: clean(b.event_code, 60) || undefined, user_tag: "Public", is_active: 1, registered_by: s.name, registered_on: istToday() };
  try {
    const erp = erpOf(c);
    const r = await erp.insert<Row>(PERSON, doc);
    c.executionCtx.waitUntil(notifyNewContact(c, r.data).catch((e) => console.error("whatsapp", e)));
    const saved = await getById(erp, r.data.name); // re-read for the dropdown titles
    return c.json({ person: (await present(erp, [saved ?? r.data]))[0] }, 201);
  } catch (e) {
    if (isDuplicate(e)) throw new HttpError(409, "This mobile number is already registered.");
    throw e;
  }
});

app.put("/people/:mob", async (c) => {
  const mob = normalizeMobile(c.req.param("mob"));
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const b = await body(c);
  const patch: Record<string, unknown> = { ...details(b), ...(await listFields(c, b, false)) };
  if (clean(b.name)) patch.full_name = clean(b.name);
  const erp = erpOf(c);
  const row = await getRow(erp, mob);
  if (!row) throw new HttpError(404, "Person not found.");
  await erp.update(PERSON, row.name, nonEmpty(patch));
  memo.delete(`p:${row.name}`);
  return c.json({ ok: true });
});

// ---------- attendance
/** Keeps the person's summary (count + last date) in step. Recomputed from the records, so it can never drift. */
async function refreshStats(erp: Erp, id: string) {
  const [count, last] = await Promise.all([
    erp.count(ATT, [["person", "=", id]]),
    erp.list<{ attendance_date: string }>(ATT, ["attendance_date"], [["person", "=", id]], { order_by: "attendance_date desc", limit_page_length: 1 }),
  ]);
  await erp.update(PERSON, id, { attendance_count: count, last_attended_on: last[0]?.attendance_date ?? null });
}

/** Client-supplied time is honoured only for recent check-ins (offline queue); anything odd falls back to "now". */
function when(b: Record<string, unknown>) {
  const now = istNow();
  const ts = typeof b.ts === "string" && TS_RE.test(b.ts) ? b.ts : now;
  const date = ts.slice(0, 10);
  if (ts > now || date < addDays(now.slice(0, 10), -7)) return { ts: now, date: now.slice(0, 10) };
  return { ts, date };
}

app.post("/attendance", async (c) => {
  const b = await body(c);
  const s = c.get("session");
  const erp = erpOf(c);
  const mob = normalizeMobile(b.mob);
  const event = clean(b.event, 60);
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  if (!event) throw bad("Choose an event.");
  const { ts, date } = when(b);

  let person = await getRow(erp, mob);
  let registered = false;
  if (!person) {
    // Register on the spot (needs at least a name and level).
    const name = clean(b.name);
    const d = details(b);
    if (!name || !d.level) throw new HttpError(404, "This number is not registered. Add the name and level to register them.", { not_registered: true });
    const doc = { mob_no: mob, full_name: name, ...d, ...(await listFields(c, b, false)), event_code: event, user_tag: "Public", is_active: 1, registered_by: s.name, registered_on: istToday() };
    try { person = (await erp.insert<Row>(PERSON, doc)).data; c.executionCtx.waitUntil(notifyNewContact(c, person).catch((e) => console.error("whatsapp", e))); } catch (e) { if (!isDuplicate(e)) throw e; person = await getRow(erp, mob); }
    registered = true;
  } else if (b.edits && typeof b.edits === "object") {
    // Volunteer corrected the details on screen: save them first.
    const e = b.edits as Record<string, unknown>;
    const patch: Record<string, unknown> = { ...details(e), ...(await listFields(c, e, false)) };
    if (clean(e.name)) patch.full_name = clean(e.name);
    const changes = nonEmpty(patch);
    if (Object.keys(changes).length) await erp.update(PERSON, person.name, changes);
    memo.delete(`p:${person.name}`);
  }

  let status: "marked" | "already" = "marked";
  if (!person) throw new HttpError(404, "Person not found.");
  const personId = person.name;
  let id = `${event}-${date}-${personId}`;
  try {
    const r = await erp.insert<{ name: string }>(ATT, { event_code: event, attendance_date: date, person: personId, marked_by: s.id, ts });
    id = r.data.name;
  } catch (e) {
    if (isDuplicate(e)) status = "already"; else throw e;
  }
  if (status === "marked") {
    c.executionCtx.waitUntil(refreshStats(erp, personId).catch((e) => console.error("refreshStats", e)));
    c.executionCtx.waitUntil(notifyCoordinators(c, personId, event, ts).catch((e) => console.error("notifyCoordinators", e)));
  }
  memo.delete(`home:${event}:${date}`);
  const guide = await guideOf(c, person.guide); // printed on the receipt
  return c.json({ status, id, registered, name: person.full_name, guide: guide?.title ?? "", guide_mobile: guide?.mobile ?? "" });
});

app.get("/attendance/today", async (c) => {
  const event = clean(c.req.query("event"), 60);
  const dq = c.req.query("date") ?? "";
  const date = DATE_RE.test(dq) ? dq : istToday();
  if (!event) throw bad("event is required");
  const rows = await cached(`today:${event}:${date}`, 3_000, () =>
    erpOf(c).list<{ name: string; person: string; person_mob?: string; person_name: string; marked_by: string; marked_by_name?: string; marked_by_mob?: string; ts: string }>(
      ATT, ["name", "person", "person_mob", "person_name", "marked_by", "marked_by_name", "marked_by_mob", "ts"],
      [["event_code", "=", event], ["attendance_date", "=", date]], { order_by: "ts desc", limit_page_length: 500 }));
  return c.json({
    date,
    items: rows.map((r) => ({ id: r.name, mob: r.person_mob ?? "", name: r.person_name, marked_by: r.marked_by_name || r.marked_by, marked_by_mob: r.marked_by_mob ?? "", ts: r.ts })),
  });
});

app.delete("/attendance/:id", async (c) => {
  const id = c.req.param("id");
  const s = c.get("session");
  const erp = erpOf(c);
  const row = await erp.get<{ name: string; person: string; marked_by: string; event_code: string; attendance_date: string }>(ATT, id);
  if (!row) return c.json({ ok: true, already_gone: true });
  if (row.marked_by !== s.id && !isStaff(s)) throw new HttpError(403, "You can only undo check-ins that you marked.");
  await erp.remove(ATT, id);
  memo.delete(`home:${row.event_code}:${row.attendance_date}`);
  memo.delete(`today:${row.event_code}:${row.attendance_date}`);
  c.executionCtx.waitUntil(refreshStats(erp, row.person).catch((e) => console.error("refreshStats", e)));
  return c.json({ ok: true });
});

// ---------- admin: people list
const SORTS: Record<string, string> = {
  newest: "registered_on desc, creation desc", oldest: "registered_on asc, creation asc", name: "full_name asc", most: "attendance_count desc", recent: "last_attended_on desc",
};

/** A list sent as "a,b,c" (IDs or fixed values), cleaned and capped. */
const listParam = (v: string | undefined, max = 50) => [...new Set((v ?? "").split(",").map((x) => clean(x, 60)).filter(Boolean))].slice(0, max);
/** Fields whose "not filled in" state can be asked for (`missing=dob,college`). */
const MISSING_FIELDS: Record<string, string> = {
  gender: "gender", level: "level", occupation: "occupation", college: "college", branch: "branch", pg: "pg", area: "area", guide: "guide", dob: "dob",
  stay: "current_stay", feedback: "feedback", comments: "comments", chanting: "chanting_rounds",
};
const ageToDob = (age: number, today: string) => { const [y, m, d] = today.split("-").map(Number); return `${String(y - age).padStart(4, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`; };

/**
 * The People table's filters. Every filter is a list of allowed values ("a,b,c" = any of them), and all filters must hold.
 * Dropdown values (college, branch, pg, area, guide) are IDs. `missing` lists fields that must be empty. Skills and interests are
 * answered by one lookup in their child table, then become a plain "name in (...)" filter.
 */
function peopleQuery(q: Record<string, string | undefined>) {
  const f: Filters = [];
  const v = (k: string) => clean(q[k], 60);
  const anyOf = (param: string, field: string, allowed?: readonly string[]) => {
    const vals = listParam(q[param]).filter((x) => !allowed || (allowed as readonly string[]).includes(x));
    if (vals.length) f.push([field, "in", vals]);
  };
  anyOf("tag", "user_tag"); anyOf("level", "level", LEVELS); anyOf("gender", "gender", GENDERS); anyOf("occupation", "occupation", OCCUPATIONS);
  anyOf("stay", "current_stay", STAYS); anyOf("feedback", "feedback", FEEDBACKS); anyOf("event", "event_code");
  anyOf("college", "college"); anyOf("branch", "branch"); anyOf("pg", "pg"); anyOf("area", "area"); anyOf("guide", "guide"); anyOf("registered_by", "registered_by");
  for (const m of listParam(q.missing, 20)) { const field = MISSING_FIELDS[m]; if (field) f.push([field, m === "chanting" ? "=" : "is", m === "chanting" ? 0 : "not set"]); }
  if (v("pending") === "1") { f.push(["is_active", "=", 0]); f.push(["registered_by", "=", "self sign-up"]); f.push(["user_tag", "not in", CONTACT_TAGS]); }
  if (v("active") === "1") f.push(["is_active", "=", 1]);
  if (v("active") === "0") f.push(["is_active", "=", 0]);
  if (v("att") === "yes") f.push(["attendance_count", ">", 0]);
  if (v("att") === "no") f.push(["attendance_count", "=", 0]);
  const sessions = whole(v("sessions_min")); if (sessions) f.push(["attendance_count", ">=", sessions]);
  const sessionsMax = whole(v("sessions_max")); if (sessionsMax) f.push(["attendance_count", "<=", sessionsMax]);
  if (DATE_RE.test(v("from"))) f.push(["registered_on", ">=", v("from")]);
  if (DATE_RE.test(v("to"))) f.push(["registered_on", "<=", v("to")]);
  if (DATE_RE.test(v("att_from"))) f.push(["last_attended_on", ">=", v("att_from")]);
  if (DATE_RE.test(v("att_to"))) f.push(["last_attended_on", "<=", v("att_to")]);
  // Age from the date of birth: "at least" means born on or before that day, "at most" means born after the day a year earlier.
  const today = istToday();
  const ageMin = whole(v("age_min")), ageMax = whole(v("age_max"));
  if (ageMin || ageMax) f.push(["dob", "is", "set"]); // an empty date counts as the earliest date, so people without one must be excluded explicitly
  if (ageMin) f.push(["dob", "<=", ageToDob(ageMin, today)]);
  if (ageMax) f.push(["dob", ">", ageToDob(ageMax + 1, today)]);
  const s = v("q").replace(/[%_]/g, "");
  const or: Filters | undefined = s ? [["full_name", "like", `%${s}%`], ["mob_no", "like", `%${s}%`]] : undefined;
  return { filters: f, or_filters: or, order_by: SORTS[v("sort")] ?? SORTS.newest, page: Math.max(1, parseInt(v("page")) || 1), skills: listParam(q.skill), interests: listParam(q.interest) };
}

/** Adds the skill / interest filters (people who have ANY of the chosen values) as a name list. Returns false when nobody can match. */
async function withMultiFilters(erp: Erp, q: ReturnType<typeof peopleQuery>): Promise<boolean> {
  for (const [ids, list] of [[q.skills, "skill"], [q.interests, "interest"]] as const) {
    if (!ids.length) continue;
    const rows = await erp.list<{ parent: string }>(MULTI[list].child, ["parent"], [["parenttype", "=", PERSON], [MULTI[list].link, "in", ids]], { parent: PERSON, limit_page_length: 0 });
    const names = [...new Set(rows.map((r) => r.parent))];
    if (!names.length) return false;
    q.filters.push(["name", "in", names]);
  }
  return true;
}

app.get("/admin/people", async (c) => {
  needAdmin(c);
  const q = peopleQuery(c.req.query());
  const erp = erpOf(c);
  if (!(await withMultiFilters(erp, q))) return c.json({ page: q.page, page_size: PAGE_SIZE, total: 0, people: [] });
  const extra = q.or_filters ? { or_filters: q.or_filters } : {};
  const [rows, tot] = await Promise.all([
    erp.list<Row>(PERSON, PERSON_FIELDS, q.filters, { ...extra, order_by: q.order_by, limit_page_length: PAGE_SIZE, limit_start: (q.page - 1) * PAGE_SIZE }),
    // Frappe v16 requires dict syntax for SQL functions in `fields`.
    erp.list<{ total: number }>(PERSON, [{ COUNT: "*", as: "total" }] as unknown as string[], q.filters, { ...extra, limit_page_length: 1 }),
  ]);
  // How many calls have been made to each person on this page (the "Calls" button; the list itself opens from /people/:mob/history).
  const ids = rows.map((r) => r.name);
  const multi = await loadMulti(erp, ids);
  const callCounts = new Map((await Promise.all(chunk(ids, 100).map((ch) => erp.list<{ person: string; n: number }>(LOG, aggregate({ COUNT: "*", as: "n" }, "person"), [["person", "in", ch]], { group_by: "person" })))).flat().map((x) => [x.person, x.n]));
  return c.json({
    page: q.page, page_size: PAGE_SIZE, total: tot[0]?.total ?? rows.length,
    people: rows.map((r) => ({ ...publicPerson(r, multi.get(r.name)), calls_count: callCounts.get(r.name) ?? 0 })),
  });
});

/** Admin edit of any detail of a person, including clearing a field and changing the mobile number. Role and enabled/disabled have their own routes. */
app.put("/admin/people/:mob", async (c) => {
  needAdmin(c);
  const s = c.get("session");
  const mob = normalizeMobile(c.req.param("mob"));
  if (!mob) throw bad("Invalid mobile number.");
  const b = await body(c);
  const erp = erpOf(c);
  const row = await getRow(erp, mob);
  if (!row) throw new HttpError(404, "Person not found.");
  const patch: Record<string, unknown> = {};
  const text = (key: string, field: string, max = 120) => { if (typeof b[key] === "string") patch[field] = clean(b[key], max); };
  const choice = (key: string, allowed: readonly string[]) => { if (typeof b[key] === "string") patch[key] = pick(b[key], allowed); };
  const whole = (key: string, min: number, max: number) => { if (b[key] !== undefined) patch[key] = intIn(b[key], min, max) ?? 0; };
  if (typeof b.name === "string") { if (!clean(b.name)) throw bad("Enter the name."); patch.full_name = clean(b.name); }
  Object.assign(patch, await listFields(c, b, true));
  if (typeof b.dob === "string") { const d = dateOfBirth(b.dob); if (b.dob && !d) throw bad("Enter a valid date of birth."); patch.dob = d ?? null; }
  text("comments", "comments", 500);
  choice("gender", GENDERS); choice("level", LEVELS); choice("occupation", OCCUPATIONS); choice("current_stay", STAYS); choice("feedback", FEEDBACKS);
  whole("age", 1, 120); whole("chanting_rounds", 0, 1000);
  if (b.new_mob !== undefined && normalizeMobile(b.new_mob) !== mob) {
    const next = normalizeMobile(b.new_mob);
    if (!next) throw bad("Enter a valid 10-digit mobile number.");
    if (mob === s.mob || mob === c.env.MAIN_ADMIN_MOB) throw new HttpError(403, "This account's mobile number can only be changed in ERPNext.");
    if (await getRow(erp, next)) throw new HttpError(409, "That mobile number already belongs to someone else.");
    patch.mob_no = next;
  }
  if (!Object.keys(patch).length) throw bad("Nothing to change.");
  c.set("log", { target: `${row.full_name} (${mob})` });
  await erp.update(PERSON, row.name, patch);
  memo.delete(`p:${row.name}`);
  return c.json({ ok: true });
});

/** Takes a contact off every coordinator's list straight away. Calls already made (and their history) are kept. */
async function dropOpenCalls(erp: Erp, person: string) {
  const open = await erp.list<{ name: string }>(ASG, ["name"], [["person", "=", person], ["status", "=", PENDING]], { limit_page_length: 0 });
  if (open.length) await erp.call("POST", "/api/method/frappe.desk.reportview.delete_items", { items: JSON.stringify(open.map((x) => x.name)), doctype: ASG });
}

app.patch("/admin/people/:mob/role", async (c) => {
  needAdmin(c);
  const s = c.get("session");
  const mob = normalizeMobile(c.req.param("mob"));
  const b = await body(c);
  const tag = clean(b.tag, 40);
  if (!mob) throw bad("Invalid mobile number.");
  if (mob === s.mob) throw new HttpError(403, "You can't change your own role.");
  if (mob === c.env.MAIN_ADMIN_MOB) throw new HttpError(403, "The main admin's role can only be changed in ERPNext.");
  if (!(await tagOptions(c)).includes(tag)) throw bad("Unknown role.");
  const erp = erpOf(c);
  const row = await getRow(erp, mob);
  if (!row) throw new HttpError(404, "Person not found.");
  await erp.update(PERSON, row.name, { user_tag: tag });
  memo.delete(`p:${row.name}`);
  if (tag === NOT_INTERESTED) await dropOpenCalls(erp, row.name);
  return c.json({ ok: true });
});

app.patch("/admin/people/:mob/active", async (c) => {
  needAdmin(c);
  const s = c.get("session");
  const mob = normalizeMobile(c.req.param("mob"));
  const b = await body(c);
  if (!mob) throw bad("Invalid mobile number.");
  if (mob === s.mob || mob === c.env.MAIN_ADMIN_MOB) throw new HttpError(403, "You can't disable this account.");
  const erp = erpOf(c);
  const row = await getRow(erp, mob);
  if (!row) throw new HttpError(404, "Person not found.");
  await erp.update(PERSON, row.name, { is_active: b.active ? 1 : 0 });
  memo.delete(`p:${row.name}`);
  return c.json({ ok: true });
});

// ---------- admin: events
app.post("/admin/events", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const name = clean(b.name, 100);
  const code = clean(b.code, 40).toUpperCase().replace(/[^A-Z0-9_-]/g, "");
  if (!name || !code) throw bad("Enter an event code and name.");
  try {
    await erpOf(c).insert("FOLK Event", { code, event_name: name, is_list: b.is_list === true ? 1 : 0 });
  } catch (e) {
    if (isDuplicate(e)) throw new HttpError(409, "An event with this code already exists.");
    throw e;
  }
  memo.delete("events");
  // Every real event gets its Registration and Feedback forms straight away (dynamic: nothing to set up by hand).
  if (b.is_list !== true) await ensureEventLinks(erpOf(c), code, name);
  return c.json({ ok: true }, 201);
});

app.post("/admin/events/:code/current", async (c) => {
  needAdmin(c);
  const code = c.req.param("code");
  const erp = erpOf(c);
  const events = await erp.list<EventRow>("FOLK Event", ["name", "is_current", "is_list"]);
  const target = events.find((e) => e.name === code);
  if (!target) throw new HttpError(404, "Event not found.");
  if (target.is_list) throw bad("A contact list cannot be the current event.");
  for (const e of events) {
    const want = e.name === code ? 1 : 0;
    if ((e.is_current ? 1 : 0) !== want) await erp.update("FOLK Event", e.name, { is_current: want });
  }
  memo.delete("events");
  return c.json({ ok: true });
});

/** One event at a glance: registrations, attendance (per day), feedback and calls. */
app.get("/admin/events/:code/summary", async (c) => {
  needAdmin(c);
  const code = c.req.param("code");
  const erp = erpOf(c);
  const ev: Filters = [["event_code", "=", code]];
  const data = await cached(`evsum:${code}`, 15_000, async () => {
    const [registered, volunteers, dinner, donors, transport, checkins, people, days, feedback, stars, assigned, calls] = await Promise.all([
      erp.count(REG, ev),
      erp.count(REG, [...ev, ["volunteer", "=", 1]]),
      erp.count(REG, [...ev, ["dinner", "=", 1]]),
      erp.count(REG, [...ev, ["donation", "=", "Opted to Donate"]]),
      erp.count(REG, [...ev, ["transport_required", "=", 1]]),
      erp.count(ATT, ev),
      erp.list<{ person: string; n: number }>(ATT, aggregate({ COUNT: "*", as: "n" }, "person"), ev, { group_by: "person", limit_page_length: 0 }),
      erp.list<{ attendance_date: string; n: number }>(ATT, aggregate({ COUNT: "*", as: "n" }, "attendance_date"), ev, { group_by: "attendance_date", order_by: "attendance_date asc", limit_page_length: 0 }),
      erp.count(FB, ev),
      erp.list<{ rating: number; n: number }>(FB, aggregate("rating", { COUNT: "*", as: "n" }), ev, { group_by: "rating", limit_page_length: 10 }),
      erp.count(ASG, ev),
      erp.count(LOG, ev),
    ]);
    const answered = stars.reduce((a, x) => a + x.n, 0);
    const average = answered ? Math.round((stars.reduce((a, x) => a + x.rating * x.n, 0) / answered) * 10) / 10 : 0;
    return {
      registered, volunteers, dinner, donors, transport,
      attended: people.length, checkins,
      days: days.map((d) => ({ date: d.attendance_date, count: d.n })),
      feedback, average, assigned, calls,
    };
  });
  return c.json(data);
});

// ---------- admin: analytics + CSV exports
app.get("/admin/analytics", async (c) => {
  needAdmin(c);
  const q = c.req.query();
  const f = { from: DATE_RE.test(q.from ?? "") ? q.from! : "", to: DATE_RE.test(q.to ?? "") ? q.to! : "", event: clean(q.event, 60), level: pick(q.level, LEVELS), gender: pick(q.gender, GENDERS) };
  const tags = await tagOptions(c);
  return c.json(await cached(`an:${JSON.stringify(f)}`, 60_000, () => analytics(erpOf(c), f, tags)));
});

const csvCell = (v: unknown) => { const s = String(v ?? ""); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; };
const csv = (cols: string[], rows: Record<string, unknown>[]) => "﻿" + [cols.join(","), ...rows.map((r) => cols.map((k) => csvCell(r[k])).join(","))].join("\r\n");
const csvResponse = (c: Ctx, name: string, text: string) =>
  c.body(text, 200, { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${name}"` });

app.get("/admin/export/people", async (c) => {
  needAdmin(c);
  const q = peopleQuery(c.req.query());
  const erp = erpOf(c);
  const rows = (await withMultiFilters(erp, q)) ? await erp.list<Row>(PERSON, PERSON_FIELDS, q.filters, { ...(q.or_filters && { or_filters: q.or_filters }), order_by: q.order_by, limit_page_length: 0 }) : [];
  const multi = await loadMulti(erp, rows.map((r) => r.name));
  const out = rows.map((r) => {
    const m = multi.get(r.name) ?? NO_MULTI;
    return { ...r, college: r.college_title ?? "", branch: r.branch_title ?? "", pg_name: r.pg_title ?? "", area: r.area_title ?? "", age: ageOn(r.dob, istToday()) ?? r.age ?? "", guide: (r.guide_title ?? "").toUpperCase(), skills: m.skills.map((o) => o.title).join(", "), interests: m.interests.map((o) => o.title).join(", ") };
  });
  return csvResponse(c, "folk-people.csv", csv(
    ["mob_no", "full_name", "gender", "level", "occupation", "college", "branch", "pg_name", "area", "guide", "guide_mobile", "event_code", "user_tag", "attendance_count", "last_attended_on", "registered_by", "registered_on", "dob", "age", "current_stay", "skills", "interests", "chanting_rounds", "feedback", "comments"], out));
});

app.get("/reports/attendance", async (c) => {
  needStaff(c);
  const event = clean(c.req.query("event"), 60);
  if (!event) throw bad("event is required");
  const rows = await erpOf(c).list<Record<string, unknown>>(ATT, ["ts", "person_mob", "person_name", "event_code", "marked_by_mob", "marked_by_name"], [["event_code", "=", event]], { order_by: "ts asc", limit_page_length: 0 });
  return csvResponse(c, `folk-attendance-${event}.csv`, csv(["ts", "person_mob", "person_name", "event_code", "marked_by_mob", "marked_by_name"], rows));
});

// ---------- admin: settings
app.get("/admin/settings", async (c) => {
  needAdmin(c);
  memo.delete("settings");
  return c.json({ settings: await loadSettings(c) });
});

app.put("/admin/settings", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const patch: Record<string, unknown> = {};
  for (const k of ["offline_queue_enabled", "auto_approve_signups", "whatsapp_enabled", "notify_coordinator_attendance"] as const) if (typeof b[k] === "boolean") patch[k] = b[k] ? 1 : 0;
  for (const k of ["welcome_template", "attendance_template"] as const) {
    if (typeof b[k] !== "string") continue;
    const v = b[k].trim();
    if (!/^[a-z0-9_]{1,60}$/.test(v)) throw bad("A template name uses only small letters, digits and underscores, exactly as in your WhatsApp account.");
    patch[k] = v;
  }
  if (b.receipt && typeof b.receipt === "object") {
    const cur = (await loadSettings(c)).receipt;
    patch.receipt_format = JSON.stringify(receiptFrom({ ...cur, ...(b.receipt as Record<string, unknown>) }));
  }
  if (b.app_update && typeof b.app_update === "object") {
    const u = b.app_update as Record<string, unknown>;
    const next = updateFrom({ ...(await loadSettings(c)).app_update, ...u });
    if (typeof u.url === "string" && u.url.trim() && !next.url) throw bad("The update link must start with https://");
    if (/^https:\/\/(drive|docs)\.google\.com|dropbox\.com|onedrive|1drv\.ms|wetransfer/i.test(next.url)) throw bad("File-sharing pages (Google Drive, Dropbox...) are not direct downloads. Use a direct link to the .apk file, for example a GitHub release.");
    if (next.min_build > next.latest_build) throw bad("The minimum build cannot be higher than the latest build.");
    patch.app_update = JSON.stringify(next);
  }
  if (!Object.keys(patch).length) throw bad("Nothing to change.");
  await erpOf(c).update("FOLK Settings", "FOLK Settings", patch);
  memo.delete("settings");
  return c.json({ ok: true, settings: await loadSettings(c) });
});

// ---------- WhatsApp: welcome message to the contact (sent in the background, never blocks the app)
/** A person just inserted has only the guide's ID: add the guide's phone (sent in the welcome message). */
const withGuideMobile = async (c: Ctx, p: Row): Promise<Row> => (p.guide_mobile ? p : { ...p, guide_mobile: (await guideOf(c, p.guide))?.mobile ?? "" });
/** Welcomes a contact who was just created or registered for an event. `eventCode` defaults to the event they were created under. */
async function notifyNewContact(c: Ctx, p: Row, eventCode = p.event_code) {
  const s = await loadSettings(c);
  if (!s.whatsapp_enabled) return;
  const events = await loadEvents(c);
  const m = welcomeMessage(await withGuideMobile(c, p), events.find((e) => e.code === eventCode)?.name ?? "", s.welcome_template, defaultsOf(c.env));
  if (m) await sendTemplate(c.env, m);
}

/** Admin: shows what would be sent for a contact, without sending anything. */
app.get("/admin/whatsapp/preview/:mob", async (c) => {
  needAdmin(c);
  const mob = normalizeMobile(c.req.param("mob"));
  const row = mob ? await getRow(erpOf(c), mob) : null;
  if (!row) throw new HttpError(404, "Person not found.");
  const events = await loadEvents(c);
  const s = await loadSettings(c);
  const m = welcomeMessage(await withGuideMobile(c, row), events.find((e) => e.code === row.event_code)?.name ?? "", s.welcome_template, defaultsOf(c.env));
  return c.json({ messages: m ? [m] : [] });
});

/** When a contact attends, tells the coordinator(s) who were assigned to call them (if the admin switched this on). */
async function notifyCoordinators(c: Ctx, personId: string, event: string, ts: string) {
  const s = await loadSettings(c);
  if (!s.notify_coordinator_attendance) return;
  const erp = erpOf(c);
  const [person, asg] = await Promise.all([
    erp.get<Row>(PERSON, personId),
    erp.list<{ coordinator: string }>(ASG, ["coordinator"], [["person", "=", personId], ["event_code", "=", event]], { limit_page_length: 5 }),
  ]);
  if (!person) return;
  const eventName = (await loadEvents(c)).find((e) => e.code === event)?.name ?? event;
  const time = new Date(ts.replace(" ", "T") + "Z").toLocaleTimeString("en-IN", { timeZone: "UTC", hour: "numeric", minute: "2-digit", hour12: true });
  for (const id of [...new Set(asg.map((a) => a.coordinator))]) {
    const co = await erp.get<Row>(PERSON, id);
    if (!co?.mob_no) continue;
    try { await sendTemplate(c.env, attendanceAlert(co, person, eventName, time, s.welcome_template, defaultsOf(c.env))); } catch (e) { console.error("whatsapp alert failed", e); }
  }
}

// =====================================================================================================
// Calling: coordinators phone the contacts an admin assigned to them, from inside the app.
// =====================================================================================================
const chunk = <T,>(a: T[], n: number) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
const aggregate = (...f: unknown[]) => f as unknown as string[]; // Frappe v16 wants dict syntax for SQL functions in `fields`

type Asg = { name: string; person: string; person_name: string; person_mob: string; coordinator: string; coordinator_name?: string; event_code: string; status: string; note?: string; is_follow_up?: number; assigned_at?: string; submitted_at?: string };
const ASG_FIELDS = ["name", "person", "person_name", "person_mob", "coordinator", "coordinator_name", "event_code", "status", "note", "is_follow_up", "assigned_at", "submitted_at"];

type Template = { id: string; heading: string; text: string; active: boolean };
async function loadTemplates(c: Ctx): Promise<Template[]> {
  return cached("templates", 30_000, async () => {
    const r = await erpOf(c).get<{ message_templates?: string }>("FOLK Settings", "FOLK Settings");
    try { const v = JSON.parse(r?.message_templates || "[]"); return Array.isArray(v) ? (v as Template[]) : []; } catch { return []; }
  });
}
const activeMessage = (t: Template[]) => (t.find((x) => x.active) ?? t[0])?.text ?? "";

const staffOnly = (c: Ctx) => needStaff(c);

app.get("/my/calls", async (c) => {
  staffOnly(c);
  const s = c.get("session");
  const erp = erpOf(c);
  const rows = await erp.list<Asg>(ASG, ASG_FIELDS, [["coordinator", "=", s.id]], { order_by: "assigned_at desc", limit_page_length: 1000 });
  const ids = [...new Set(rows.map((r) => r.person))];
  const since = new Date(Date.now() + 5.5 * 3600_000 - 28 * 86400_000).toISOString().replace("T", " ").slice(0, 19);
  type PInfo = { name: string; level?: string; venue?: string; pg_name?: string; profession?: string; attendance_count?: number; last_attended_on?: string };
  const [people, counts, events, templates] = await Promise.all([
    Promise.all(chunk(ids, 100).map((ch) => erp.list<PInfo>(PERSON, ["name", "level", "area.title as venue", "pg.title as pg_name", "college.title as profession", "attendance_count", "last_attended_on"], [["name", "in", ch]]))),
    Promise.all(chunk(ids, 100).map((ch) => erp.list<{ person: string; n: number }>(LOG, aggregate({ COUNT: "*", as: "n" }, "person"), [["person", "in", ch], ["called_at", ">=", since]], { group_by: "person" }))),
    loadEvents(c), loadTemplates(c),
  ]);
  const info = new Map(people.flat().map((p) => [p.name, p]));
  const calls = new Map(counts.flat().map((x) => [x.person, x.n]));
  const evName = new Map(events.map((e) => [e.code, e.name]));
  const items = rows.map((r) => {
    const p = info.get(r.person);
    return {
      id: r.name, mob: r.person_mob, name: r.person_name, event_code: r.event_code, event_name: evName.get(r.event_code) ?? r.event_code,
      status: r.status || PENDING, note: r.note ?? "", is_follow_up: !!r.is_follow_up, assigned_at: r.assigned_at ?? "", submitted_at: r.submitted_at ?? "",
      level: p?.level ?? "", venue: p?.venue ?? "", pg_name: p?.pg_name ?? "", profession: p?.profession ?? "",
      sessions: p?.attendance_count ?? 0, last_attended_on: p?.last_attended_on ?? "", calls_28d: calls.get(r.person) ?? 0,
    };
  });
  return c.json({ items, message_text: activeMessage(templates), statuses: STATUSES, positive: POSITIVE, follow_up: FOLLOW_UP, note_required: NOTE_REQUIRED });
});

/** Home-page numbers for a coordinator: who they have called for an event, and which of those came to it. */
app.get("/my/calls/summary", async (c) => {
  staffOnly(c);
  const s = c.get("session");
  const event = clean(c.req.query("event"), 60);
  if (!event) throw bad("event is required");
  const erp = erpOf(c);
  const weekly = (await loadEvents(c)).find((e) => e.code === event)?.weekly; // a weekly event counts only this Monday-Sunday
  const since: Filters = weekly ? [["submitted_at", ">=", `${istWeek().from} 00:00:00`]] : [];
  const rows = await erp.list<Asg>(ASG, ASG_FIELDS, [["coordinator", "=", s.id], ["event_code", "=", event], ["status", "!=", PENDING], ...since], { order_by: "submitted_at desc", limit_page_length: 0 });
  const ids = [...new Set(rows.map((r) => r.person))];
  const att = (await Promise.all(chunk(ids, 100).map((ch) => erp.list<{ person: string; ts: string }>(ATT, ["person", "ts"], [["event_code", "=", event], ["person", "in", ch]], { order_by: "ts asc" })))).flat();
  const came = new Map<string, string>();
  for (const a of att) if (!came.has(a.person)) came.set(a.person, a.ts);
  const calls = rows.map((r) => ({ id: r.name, name: r.person_name, mob: r.person_mob, status: r.status, called_at: r.submitted_at ?? "", came: came.has(r.person), came_at: came.get(r.person) ?? "" }));
  return c.json({ called: calls.length, came: calls.filter((x) => x.came).length, calls });
});

/**
 * Calling progress for an event: for every coordinator who was given contacts, how many calls are done and how many are still waiting.
 * Staff only; it returns names and counts, never phone numbers. A weekly event counts only this Monday-Sunday (plus everything still waiting).
 */
app.get("/calls/progress", async (c) => {
  staffOnly(c);
  const event = clean(c.req.query("event"), 60);
  if (!event) throw bad("event is required");
  const erp = erpOf(c);
  const weekly = !!(await loadEvents(c)).find((e) => e.code === event)?.weekly;
  type N = { coordinator: string; status: string; n: number };
  const count = (f: Filters) => erp.list<N>(ASG, aggregate({ COUNT: "*", as: "n" }, "coordinator", "status"), [["event_code", "=", event], ...f], { group_by: "coordinator, status" });
  // Is each coordinator calling in time? The latest call they made, and how long their oldest waiting contact has been waiting.
  const edge = (fn: "MAX" | "MIN", field: string, as: string, f: Filters) =>
    erp.list<{ coordinator: string } & Record<string, string>>(ASG, aggregate({ [fn]: field, as }, "coordinator"), [["event_code", "=", event], ...f], { group_by: "coordinator" });
  const [rows, names, lasts, waits] = await Promise.all([
    weekly
      ? Promise.all([count([["status", "=", PENDING]]), count([["status", "!=", PENDING], ["submitted_at", ">=", `${istWeek().from} 00:00:00`]])]).then((p) => p.flat())
      : count([]),
    erp.list<{ name: string; full_name: string }>(PERSON, ["name", "full_name"], [["user_tag", "in", ["Coordinator", "Admin"]]]),
    edge("MAX", "submitted_at", "at", [["status", "!=", PENDING]]),
    edge("MIN", "assigned_at", "at", [["status", "=", PENDING]]),
  ]);
  const lastCall = new Map(lasts.map((x) => [x.coordinator, x.at ?? ""]));
  const waitingSince = new Map(waits.map((x) => [x.coordinator, x.at ?? ""]));
  const nm = new Map(names.map((x) => [x.name, x.full_name]));
  const by = new Map<string, { id: string; name: string; done: number; pending: number }>();
  for (const r of rows) {
    const x = by.get(r.coordinator) ?? { id: r.coordinator, name: nm.get(r.coordinator) ?? "Earlier system (imported)", done: 0, pending: 0 };
    if (r.status === PENDING) x.pending += r.n; else x.done += r.n;
    by.set(r.coordinator, x);
  }
  const pct = (done: number, total: number) => (total ? Math.round((done / total) * 100) : 0);
  const coordinators = [...by.values()].map((x) => ({ ...x, assigned: x.done + x.pending, percent: pct(x.done, x.done + x.pending), complete: x.pending === 0, last_call: lastCall.get(x.id) ?? "", waiting_since: waitingSince.get(x.id) ?? "" }))
    .sort((a, b) => b.percent - a.percent || b.done - a.done || a.name.localeCompare(b.name));
  const done = coordinators.reduce((t, x) => t + x.done, 0), pending = coordinators.reduce((t, x) => t + x.pending, 0);
  return c.json({ totals: { assigned: done + pending, done, pending, percent: pct(done, done + pending) }, coordinators });
});

/**
 * The contacts handed to one coordinator for an event, with each one's state: still waiting, or called (and when). Staff only.
 * Names only, never phone numbers (like the progress list). A weekly event shows what is waiting plus what was called this week.
 */
app.get("/calls/coordinator", async (c) => {
  staffOnly(c);
  const event = clean(c.req.query("event"), 60);
  const who = clean(c.req.query("id"), 60);
  if (!event || !who) throw bad("event and id are required");
  const erp = erpOf(c);
  const weekly = !!(await loadEvents(c)).find((e) => e.code === event)?.weekly;
  const rows = await erp.list<Asg>(ASG, ASG_FIELDS, [["event_code", "=", event], ["coordinator", "=", who]], { order_by: "assigned_at asc", limit_page_length: 0 });
  const from = weekly ? `${istWeek().from} 00:00:00` : "";
  const contacts = rows
    .filter((r) => r.status === PENDING || !from || (r.submitted_at ?? "") >= from)
    .map((r) => ({ id: r.name, name: r.person_name, status: r.status, pending: r.status === PENDING, follow_up: !!r.is_follow_up, assigned_at: r.assigned_at ?? "", called_at: r.status === PENDING ? "" : r.submitted_at ?? "" }));
  const [p] = await erp.list<{ full_name: string }>(PERSON, ["full_name"], [["name", "=", who]], { limit_page_length: 1 });
  return c.json({ name: p?.full_name ?? "Earlier system (imported)", contacts });
});

/** One call outcome. Safe to retry: client_ref is unique, so the log can never get a second row for the same tap. */
app.post("/my/calls/:id/submit", async (c) => {
  staffOnly(c);
  const s = c.get("session");
  const b = await body(c);
  const status = clean(b.status, 60);
  const note = clean(b.note, 1000);
  const ref = clean(b.client_ref, 64);
  if (!(STATUSES as readonly string[]).includes(status) || status === PENDING) throw bad("Choose a call status.");
  if (NOTE_REQUIRED.includes(status) && !note) throw bad("Please write a note for this status.");
  if (ref.length < 8) throw bad("Invalid request.");
  const erp = erpOf(c);
  const a = await erp.get<Asg>(ASG, c.req.param("id"));
  if (!a) throw new HttpError(404, "This call is no longer assigned to you.");
  if (a.coordinator !== s.id && !isAdmin(s)) throw new HttpError(403, "This contact is assigned to someone else.");
  const now = istNow();
  try {
    await erp.insert(LOG, { client_ref: ref, person: a.person, coordinator: s.id, event_code: a.event_code, status, note, called_at: now });
  } catch (e) {
    if (!isDuplicate(e)) throw e; // already saved by an earlier attempt
  }
  await erp.update(ASG, a.name, { status, note, submitted_at: now });
  let marked = false;
  if (status === NOT_INTERESTED) {
    // The contact said no: move them to the "Not Interested" role so nobody is asked to call them again.
    // Only plain contacts change; a coordinator or admin who was assigned by mistake keeps their role.
    const p = await erp.get<{ name: string; user_tag?: string }>(PERSON, a.person);
    if (p && (p.user_tag || "Public") === "Public") {
      await erp.update(PERSON, p.name, { user_tag: NOT_INTERESTED });
      memo.delete(`p:${p.name}`);
      await dropOpenCalls(erp, p.name);
      marked = true;
    }
  }
  return c.json({ ok: true, status, submitted_at: now, marked_not_interested: marked });
});

/** Earlier calls and attended sessions for a contact (the popups on a call card). */
app.get("/people/:mob/history", async (c) => {
  staffOnly(c);
  const mob = normalizeMobile(c.req.param("mob"));
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const erp = erpOf(c);
  const [calls, sessions, registrations] = await Promise.all([
    erp.list<{ called_at: string; status: string; note?: string; coordinator_name?: string; legacy_caller?: string; event_code?: string }>(LOG, ["called_at", "status", "note", "coordinator_name", "legacy_caller", "event_code"], [["person_mob", "=", mob]], { order_by: "called_at desc", limit_page_length: 50 }),
    erp.list<{ ts: string; event_code: string; marked_by_name?: string }>(ATT, ["ts", "event_code", "marked_by_name"], [["person_mob", "=", mob]], { order_by: "ts desc", limit_page_length: 50 }),
    erp.list<Record<string, unknown>>(REG, REG_COLS, [["person_mob", "=", mob]], { order_by: "registered_at desc", limit_page_length: 50 }),
  ]);
  return c.json({ calls: calls.map((x) => ({ ...x, coordinator_name: x.coordinator_name || x.legacy_caller || "" })), sessions, registrations });
});

// ---------- admin: callers
app.get("/admin/callers", async (c) => {
  needAdmin(c);
  const erp = erpOf(c);
  const event = clean(c.req.query("event"), 60); // counts are for this event; without it, for all events
  const [people, counts] = await Promise.all([
    erp.list<Row & { call_limit?: number; auto_assign?: number }>(PERSON, ["name", "mob_no", "full_name", "gender", "call_limit", "auto_assign"], [["user_tag", "=", "Coordinator"], ["is_active", "=", 1]], { order_by: "full_name asc" }),
    erp.list<{ coordinator: string; status: string; n: number }>(ASG, aggregate({ COUNT: "*", as: "n" }, "coordinator", "status"), event ? [["event_code", "=", event]] : [], { group_by: "coordinator, status" }),
  ]);
  const by = new Map<string, { assigned: number; pending: number; positive: number }>();
  for (const r of counts) {
    const x = by.get(r.coordinator) ?? { assigned: 0, pending: 0, positive: 0 };
    x.assigned += r.n;
    if (r.status === PENDING) x.pending += r.n;
    if (POSITIVE.includes(r.status)) x.positive += r.n;
    by.set(r.coordinator, x);
  }
  return c.json({
    statuses: STATUSES.filter((x) => x !== PENDING),
    callers: people.map((p) => ({ id: p.name, mob: p.mob_no, name: p.full_name, gender: p.gender ?? "", call_limit: p.call_limit || null, enabled: p.auto_assign !== 0, ...(by.get(p.name) ?? { assigned: 0, pending: 0, positive: 0 }) })),
  });
});

app.patch("/admin/callers/:mob", async (c) => {
  needAdmin(c);
  const mob = normalizeMobile(c.req.param("mob"));
  const b = await body(c);
  const erp = erpOf(c);
  const row = mob ? await getRow(erp, mob) : null;
  if (!row) throw new HttpError(404, "Person not found.");
  const patch: Record<string, unknown> = {};
  if ("call_limit" in b) {
    const n = b.call_limit === null || b.call_limit === "" ? null : Math.floor(Number(b.call_limit));
    if (n !== null && (!Number.isFinite(n) || n < 1 || n > 1000)) throw bad("Call limit must be between 1 and 1000.");
    patch.call_limit = n;
  }
  if (typeof b.enabled === "boolean") {
    // "Enabled" = can be given calls. A coordinator who still holds calls nobody has made cannot be switched off until those are moved or removed.
    if (!b.enabled) {
      const waiting = await erp.count(ASG, [["coordinator", "=", row.name], ["status", "=", PENDING]]);
      if (waiting > 0) throw bad(`${row.full_name} still has ${waiting} call${waiting === 1 ? "" : "s"} nobody has made. Move them to another coordinator or remove them first.`);
    }
    patch.auto_assign = b.enabled ? 1 : 0;
  }
  await erp.update(PERSON, row.name, patch);
  return c.json({ ok: true });
});

// ---------- admin: assigning contacts (wizard)
//
// Three kinds of hand-out, all built the same way: (1) PLAN: the server works out exactly who gets which contact and returns it,
// without writing anything; (2) APPLY: the app sends that plan back in small batches. Each batch is safe to repeat, so a dropped
// connection never leaves a half-done mess. Nothing already assigned is ever removed by a new hand-out; it goes on top.
//   assign   contacts nobody has been given yet for this event, narrowed by filters, up to `limit` of them
//   followup contacts whose last call had one of the chosen statuses (optionally within a date range), for another try
//   move     untouched calls of chosen coordinators (or of everyone when `all`) go to other coordinators
// A coordinator's call limit is the most they can hold for the event: what they already have counts against it.
type Kind = "assign" | "followup" | "move";
type To = { keep_previous: boolean; coordinators: string[] };
type AssignBody = {
  kind: Kind; event: string; filters: PoolFilter[]; statuses: string[]; date_from: string; date_to: string; from: string[]; include_new: boolean; all: boolean;
  limit: number; to: To;
};
/** The fields a hand-out can be narrowed by. Fixed here so the app can never ask for anything else. */
const POOL_FIELDS = ["college", "branch", "area", "level", "gender", "occupation", "guide", "reg_event", "attended", "skill", "interest"] as const;
const arr = (v: unknown, max = 5000) => (Array.isArray(v) ? v.map((x) => String(x)).slice(0, max) : []);
const whole = (v: unknown) => { const n = Math.floor(Number(v)); return Number.isFinite(n) && n > 0 ? Math.min(n, 100000) : 0; };
const rec = (v: unknown): Record<string, unknown> => (v && typeof v === "object" ? (v as Record<string, unknown>) : {});

function parseFilters(v: unknown): PoolFilter[] {
  return (Array.isArray(v) ? v : []).slice(0, 20).flatMap((x) => {
    const f = rec(x);
    const field = (POOL_FIELDS as readonly string[]).find((n) => n === f.field);
    return field ? [{ field, mode: f.mode === "except" ? "except" as const : "only" as const, values: arr(f.values, 2000) }] : [];
  });
}
function assignBody(b: Record<string, unknown>): AssignBody {
  const kind = (["assign", "followup", "move"] as const).find((x) => x === b.kind);
  if (!kind) throw bad("Choose what you want to do.");
  const date = (v: unknown) => (DATE_RE.test(String(v ?? "")) ? String(v) : "");
  const to = rec(b.to);
  return {
    kind, event: clean(b.event, 60), filters: parseFilters(b.filters),
    statuses: arr(b.statuses, 20).filter((x) => (STATUSES as readonly string[]).includes(x) && x !== PENDING),
    date_from: date(b.date_from), date_to: date(b.date_to),
    from: arr(b.from, 200).map((m) => normalizeMobile(m) ?? "").filter(Boolean), include_new: b.include_new === true, all: b.all === true,
    limit: whole(b.limit),
    to: { keep_previous: to.keep_previous === true, coordinators: arr(to.coordinators, 200).map((m) => normalizeMobile(m) ?? "").filter(Boolean) },
  };
}

/**
 * Updates many records with one ERPNext call per 200 rows. Updating them one by one would hit Cloudflare's
 * limit on outgoing requests per invocation (50) as soon as an assignment moves more than a few dozen contacts.
 */
async function bulkUpdate(erp: Erp, doctype: string, rows: ({ name: string } & Record<string, unknown>)[]) {
  for (const part of chunk(rows, 200)) {
    const docs = part.map(({ name, ...fields }) => ({ doctype, docname: name, ...fields }));
    const r = await erp.call("POST", "/api/method/frappe.client.bulk_update", { docs: JSON.stringify(docs) }); // Frappe expects the list as text
    const failed = (r?.message?.failed_docs as unknown[] | undefined)?.length ?? 0;
    if (failed) throw new HttpError(502, `Could not update ${failed} of ${docs.length} records. Please try again.`);
  }
}

type Coordinator = Row & { gender?: string; call_limit?: number; auto_assign?: number };
const COORD_FIELDS = ["name", "mob_no", "full_name", "gender", "call_limit", "auto_assign"];
/** Calls are never handed to women, whatever was selected (the app hides them too; this is the real rule). */
const canReceiveCalls = (p: { gender?: string }) => p.gender !== "F";

type PoolItem = { person: string; row?: Asg; attrs: Attrs };
type PoolData = { items: PoolItem[]; coords: Coordinator[]; existing: Asg[]; assigned: number };

/** The contacts a hand-out can draw from (before the admin's filters), with the values the filters look at. */
async function loadPool(c: Ctx, a: AssignBody, extraField = ""): Promise<PoolData> {
  if (!a.event) throw bad("Choose the event these calls are for.");
  if (a.date_from && a.date_to && a.date_from > a.date_to) throw bad("The 'from' date is after the 'to' date.");
  const erp = erpOf(c);
  const needs = (list: "skill" | "interest") => extraField === list || a.filters.some((f) => f.field === list);
  const multi = (list: "skill" | "interest") => needs(list)
    ? erp.list<{ parent: string; id: string }>(MULTI[list].child, ["parent", `${MULTI[list].link} as id`], [["parenttype", "=", PERSON]], { parent: PERSON })
    : Promise.resolve([] as { parent: string; id: string }[]);
  const [people, existing, coords, skills, interests] = await Promise.all([
    erp.list<Row>(PERSON, ["name", "college", "branch", "area", "level", "gender", "occupation", "guide", "event_code", "attendance_count"], [["user_tag", "=", "Public"], ["is_active", "=", 1]], { order_by: "creation asc" }), // staff and "Not Interested" contacts are never called
    erp.list<Asg>(ASG, ASG_FIELDS, [["event_code", "=", a.event]]),
    erp.list<Coordinator>(PERSON, COORD_FIELDS, [["user_tag", "=", "Coordinator"], ["is_active", "=", 1]]),
    multi("skill"), multi("interest"),
  ]);
  const ids = (rows: { parent: string; id: string }[]) => { const m = new Map<string, string[]>(); for (const r of rows) m.set(r.parent, [...(m.get(r.parent) ?? []), r.id]); return m; };
  const sk = ids(skills), it = ids(interests);
  const have = new Map(existing.map((e) => [e.person, e]));
  const fromIds = new Set(a.all ? [] : coords.filter((p) => a.from.includes(p.mob_no)).map((p) => p.name));
  const attrsOf = (p: Row): Attrs => ({
    college: [p.college ?? ""], branch: [p.branch ?? ""], area: [p.area ?? ""], level: [p.level ?? ""], gender: [p.gender ?? ""], occupation: [p.occupation ?? ""],
    guide: [p.guide ?? ""], reg_event: [p.event_code ?? ""], attended: [(p.attendance_count ?? 0) > 0 ? "yes" : "no"],
    skill: sk.get(p.name) ?? [], interest: it.get(p.name) ?? [],
  });
  const items: PoolItem[] = [];
  let assigned = 0; // contacts that already have an assignment for this event
  for (const p of people) {
    const row = have.get(p.name);
    if (row) assigned++;
    let ok: boolean;
    if (a.kind === "assign") ok = !row; // only contacts nobody has been given yet for this event; what is assigned stays
    else if (a.kind === "followup") {
      const day = (row?.submitted_at ?? "").slice(0, 10);
      ok = !!row && a.statuses.includes(row.status) && (!(a.date_from || a.date_to) || !!day) && (!a.date_from || day >= a.date_from) && (!a.date_to || day <= a.date_to);
    } else ok = row ? row.status === PENDING && (a.all || fromIds.has(row.coordinator)) : a.include_new;
    if (ok) items.push({ person: p.name, row, attrs: attrsOf(p) });
  }
  return { items, coords, existing, assigned };
}

const GENDER_TITLE: Record<string, string> = { M: "Male", F: "Female" };
/** Numbers only: how many of the matching contacts have each value of one field (never names). */
app.post("/admin/assign/breakdown", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const a = assignBody(b);
  const field = (POOL_FIELDS as readonly string[]).find((n) => n === b.field);
  const base_ = Array.isArray(b.base_filters) ? parseFilters(b.base_filters) : null; // the filters that decide which values are listed (the caller leaves out the field's own)
  const { items, assigned } = await loadPool(c, a, field ?? "");
  const total = items.filter((i) => passes(i.attrs, a.filters)).length;
  if (!field) return c.json({ total, remaining: items.length, assigned });
  const base = items.filter((i) => passes(i.attrs, base_ ?? a.filters.filter((f) => f.field !== field)));
  const count = new Map<string, number>();
  for (const i of base) for (const v of new Set(i.attrs[field]?.length ? i.attrs[field] : [""])) count.set(v, (count.get(v) ?? 0) + 1);
  const o = await loadOptions(c);
  const titles = new Map<string, string>();
  if (field === "college" || field === "branch" || field === "area" || field === "skill" || field === "interest") for (const x of o[field]) titles.set(x.id, x.title);
  else if (field === "guide") for (const x of o.guide) titles.set(x.id, x.title);
  else if (field === "reg_event") for (const e of await loadEvents(c)) titles.set(e.code, e.name);
  else if (field === "gender") for (const k of Object.keys(GENDER_TITLE)) titles.set(k, GENDER_TITLE[k]!);
  else if (field === "attended") { titles.set("yes", "Has attended"); titles.set("no", "Never attended"); }
  const values = [...count].filter(([id]) => id !== "").map(([id, n]) => ({ id, title: titles.get(id) ?? id, count: n })).sort((x, y) => y.count - x.count || x.title.localeCompare(y.title));
  return c.json({ field, total, remaining: items.length, assigned, base: base.length, empty: count.get("") ?? 0, values });
});

/** Calls are given only to coordinators the admin has not switched off. */
const receives = (p: Coordinator) => canReceiveCalls(p) && p.auto_assign !== 0;

/** Works out who gets which contact. Writes nothing. */
async function planAssign(c: Ctx, a: AssignBody) {
  if (a.kind === "followup" && !a.statuses.length) throw bad("Choose at least one call status.");
  if (a.kind === "move" && !a.all && !a.from.length) throw bad("Choose whose calls to move.");
  if (!a.to.coordinators.length) throw bad("Choose at least one coordinator.");
  const erp = erpOf(c);
  const { items: all, coords, existing } = await loadPool(c, a);
  const byMob = new Map(coords.map((p) => [p.mob_no, p]));
  const nameOf = new Map(coords.map((p) => [p.name, p.full_name]));
  const fromIds = new Set(a.all ? [] : coords.filter((p) => a.from.includes(p.mob_no)).map((p) => p.name));
  const pool = all.filter((i) => passes(i.attrs, a.filters));

  // Who had them before (only needed when "same coordinator as before" is on).
  const before = new Map<string, string>();
  if (a.to.keep_previous) {
    for (const i of pool) { if (i.row) before.set(i.person, i.row.coordinator); } // this event's current call first, then earlier events and calls
    if (a.kind !== "followup") {
      const [earlier, logs] = await Promise.all([
        erp.list<{ person: string; coordinator: string }>(ASG, ["person", "coordinator"], [["event_code", "!=", a.event]], { order_by: "assigned_at asc" }),
        erp.list<{ person: string; coordinator: string }>(LOG, ["person", "coordinator"], [["coordinator", "!=", ""]], { order_by: "called_at asc" }),
      ]);
      for (const r of logs) if (!before.has(r.person)) before.set(r.person, r.coordinator);
      for (const r of earlier) if (!before.has(r.person)) before.set(r.person, r.coordinator);
    }
  }

  // What each coordinator already holds for this event counts against their call limit (blank limit = no limit).
  const has = new Map<string, number>();
  for (const e of existing) has.set(e.coordinator, (has.get(e.coordinator) ?? 0) + 1);
  const members: Member[] = [];
  const info = new Map<string, { limit: number | null; has: number }>();
  for (const mob of new Set(a.to.coordinators)) {
    const p = byMob.get(mob);
    if (!p || !receives(p) || fromIds.has(p.name)) continue; // women, switched-off, unknown people and the coordinators being emptied never receive
    const held = has.get(p.name) ?? 0;
    const limit = p.call_limit || null;
    info.set(p.name, { limit, has: held });
    members.push({ id: p.name, name: p.full_name, min: 0, max: limit ? Math.max(0, limit - held) : Infinity });
  }
  if (!members.length) throw bad("None of the chosen coordinators can receive calls (women and switched-off coordinators are skipped).");

  const wanted = a.limit ? Math.min(a.limit, pool.length) : pool.length; // "how many contacts": the rest stay unassigned
  const chosen = shuffle(pool).slice(0, wanted);
  const given = new Map<string, number>();
  const r = shareOut(chosen, members, given, a.to.keep_previous ? (i) => before.get(i.person) : undefined);
  const moves = new Map<string, string[]>();
  const taken = new Map<string, number>();
  for (const x of r.given) {
    moves.set(x.coordinator, [...(moves.get(x.coordinator) ?? []), x.item.person]);
    if (x.item.row) taken.set(x.item.row.coordinator, (taken.get(x.item.row.coordinator) ?? 0) + 1);
  }
  return {
    kind: a.kind, event: a.event, follow_up: a.kind === "followup", allow: a.kind === "followup" ? a.statuses : a.kind === "assign" ? [] : [PENDING],
    candidates: pool.length, wanted, assignable: r.given.length, leftover: r.left.length, kept_with_previous: r.kept,
    per_coordinator: members.map((m) => ({ id: m.id, name: m.name, add: given.get(m.id) ?? 0, has: info.get(m.id)!.has, limit: info.get(m.id)!.limit, full: m.max === 0 }))
      .sort((x, y) => y.add - x.add),
    taken_from: [...taken].map(([id, n]) => ({ name: nameOf.get(id) ?? "Earlier system (imported)", count: n })).sort((x, y) => y.count - x.count),
    moves: [...moves].map(([coordinator, persons]) => ({ coordinator, persons })),
  };
}

app.post("/admin/assign/plan", async (c) => { needAdmin(c); return c.json(await planAssign(c, assignBody(await body(c)))); });

/**
 * Writes one batch of a plan (at most 100 contacts). Safe to repeat: contacts that already have a call row are updated, the rest
 * are created, and a row whose call was made since the plan was drawn up is left alone and counted as `skipped`.
 */
app.post("/admin/assign/apply", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const event = clean(b.event, 60);
  if (!event) throw bad("Choose an event.");
  const follow = b.follow_up === true;
  const allow = arr(b.allow, 20).filter((x) => (STATUSES as readonly string[]).includes(x));
  const pairs: { person: string; coordinator: string }[] = [];
  for (const m of Array.isArray(b.moves) ? (b.moves as Record<string, unknown>[]).slice(0, 100) : [])
    for (const p of arr(m.persons, 100)) pairs.push({ person: p, coordinator: String(m.coordinator ?? "") });
  if (!pairs.length) return c.json({ applied: 0, skipped: 0 });
  if (pairs.length > 100) throw bad("Send at most 100 contacts at a time.");

  const erp = erpOf(c);
  const ids = [...new Set(pairs.map((p) => p.person))];
  const [coords, people, rows] = await Promise.all([
    erp.list<{ name: string; gender?: string }>(PERSON, ["name", "gender"], [["name", "in", [...new Set(pairs.map((p) => p.coordinator))]], ["user_tag", "=", "Coordinator"], ["is_active", "=", 1], ["auto_assign", "=", 1]]),
    erp.list<{ name: string }>(PERSON, ["name"], [["name", "in", ids], ["user_tag", "=", "Public"], ["is_active", "=", 1]]),
    erp.list<Asg>(ASG, ASG_FIELDS, [["event_code", "=", event], ["person", "in", ids]], { limit_page_length: 0 }),
  ]);
  const okCoord = new Set(coords.filter(canReceiveCalls).map((x) => x.name));
  const okPerson = new Set(people.map((x) => x.name));
  const have = new Map(rows.map((r) => [r.person, r]));
  const now = istNow();
  const fresh: Record<string, unknown>[] = [];
  const update: ({ name: string } & Record<string, unknown>)[] = [];
  let skipped = 0;
  const added = new Map<string, number>();
  for (const p of pairs) {
    if (!okCoord.has(p.coordinator) || !okPerson.has(p.person)) { skipped++; continue; }
    const row = have.get(p.person);
    if (!row) fresh.push({ doctype: ASG, person: p.person, coordinator: p.coordinator, event_code: event, status: PENDING, is_follow_up: follow ? 1 : 0, assigned_at: now });
    else if (allow.includes(row.status || PENDING)) update.push({ name: row.name, coordinator: p.coordinator, status: PENDING, assigned_at: now, is_follow_up: follow ? 1 : 0 });
    else { skipped++; continue; }
    added.set(p.coordinator, (added.get(p.coordinator) ?? 0) + 1);
  }
  if (fresh.length) {
    try { await erp.call("POST", "/api/method/frappe.client.insert_many", { docs: fresh }); }
    catch (e) {
      // A repeat (or a second admin) may have created some of these already: keep those, insert the rest.
      if (!isDuplicate(e)) throw e;
      const taken = new Set((await erp.list<{ person: string }>(ASG, ["person"], [["event_code", "=", event], ["person", "in", fresh.map((d) => String(d.person))]], { limit_page_length: 0 })).map((x) => x.person));
      const rest = fresh.filter((d) => !taken.has(String(d.person)));
      skipped += fresh.length - rest.length;
      if (rest.length) await erp.call("POST", "/api/method/frappe.client.insert_many", { docs: rest });
    }
  }
  await bulkUpdate(erp, ASG, update);
  return c.json({ applied: fresh.length + update.length, skipped, added: Object.fromEntries(added) });
});

/**
 * Called once by the app when a whole plan has been applied (the plan is saved in many batches, so this is the one place to tell
 * coordinators). `counts` is {coordinator id: contacts added}. Each coordinator gets exactly one notification.
 */
app.post("/admin/assign/finish", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const counts = new Map<string, number>();
  if (b.counts && typeof b.counts === "object")
    for (const [id, n] of Object.entries(b.counts as Record<string, unknown>).slice(0, 300)) { const k = Math.floor(Number(n)); if (k > 0) counts.set(id, k); }
  const erp = erpOf(c);
  const env = c.env;
  c.executionCtx.waitUntil((async () => {
    const people = await erp.list<{ name: string }>(PERSON, ["name"], [["name", "in", [...counts.keys()]], ["user_tag", "=", "Coordinator"], ["is_active", "=", 1]]);
    for (const p of people) {
      const n = counts.get(p.name) ?? 0;
      await pushTo(env, erp, [p.name], "Contacts assigned to you", `${n} contact${n === 1 ? " is" : "s are"} assigned to you. Please call.`, { route: "/calls" });
    }
  })().catch((e) => console.error("notifyAssigned", e)));
  return c.json({ ok: true });
});

/** Removes assignments nobody has called yet (optionally only one coordinator's). Contacts and call history are untouched. */
app.post("/admin/assign/unassign", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const event = clean(b.event, 60);
  const mob = normalizeMobile(b.coordinator);
  if (!event && !mob) throw bad("Choose an event.");
  const erp = erpOf(c);
  // Normally only untouched calls go (a coordinator without an event: all their untouched calls, in every event). With `all` and an
  // event, every assignment of that event goes, called ones too; the call logs (history) are never touched.
  const f: Filters = b.all === true && event ? [] : [["status", "=", PENDING]];
  if (event) f.push(["event_code", "=", event]);
  if (mob) { const r = await getRow(erp, mob); if (!r) throw new HttpError(404, "Coordinator not found."); f.push(["coordinator", "=", r.name]); }
  // ERPNext deletes more than 10 records in the background, which leaves counts stale for a while. Deleting 10 at a time finishes
  // before this answers, so what the app shows next is right. One call removes at most 300; `more` tells the app to call again.
  const BATCH = 300;
  const rows = await erp.list<{ name: string }>(ASG, ["name"], f, { limit_page_length: BATCH });
  const parts = chunk(rows.map((r) => r.name), 10);
  for (const group of chunk(parts, 5)) {
    await Promise.all(group.map((part) => erp.call("POST", "/api/method/frappe.desk.reportview.delete_items", { items: JSON.stringify(part), doctype: ASG })));
  }
  return c.json({ removed: rows.length, more: rows.length === BATCH });
});

app.get("/admin/calls/stats", async (c) => {
  needAdmin(c);
  const event = clean(c.req.query("event"), 60);
  const from = DATE_RE.test(c.req.query("from") ?? "") ? c.req.query("from")! : "";
  const to = DATE_RE.test(c.req.query("to") ?? "") ? c.req.query("to")! : "";
  const erp = erpOf(c);
  // A weekly event (Saturday Satsang) shows this Monday-Sunday only; next Monday it starts again from zero. Nothing is deleted.
  const weekly = !!event && !!(await loadEvents(c)).find((e) => e.code === event)?.weekly;
  const week = istWeek();
  const [wFrom, wTo] = weekly ? [from || week.from, to || week.to] : [from, to];
  const af: Filters = event ? [["event_code", "=", event]] : [];
  const lf: Filters = [...af];
  if (wFrom) lf.push(["called_at", ">=", `${wFrom} 00:00:00`]);
  if (wTo) lf.push(["called_at", "<=", `${wTo} 23:59:59`]);
  type AsgCount = { coordinator: string; status: string; n: number };
  const countAsg = (f: Filters) => erp.list<AsgCount>(ASG, aggregate({ COUNT: "*", as: "n" }, "coordinator", "status"), f, { group_by: "coordinator, status" });
  // Weekly: everything still waiting for a call, plus what was called this week.
  const asgRows = weekly
    ? Promise.all([countAsg([...af, ["status", "=", PENDING]]), countAsg([...af, ["status", "!=", PENDING], ["submitted_at", ">=", `${wFrom} 00:00:00`]])]).then((p) => p.flat())
    : countAsg(af);
  const [asg, logs, names] = await Promise.all([
    asgRows,
    erp.list<{ coordinator: string; status: string; n: number }>(LOG, aggregate({ COUNT: "*", as: "n" }, "coordinator", "status"), lf, { group_by: "coordinator, status" }),
    erp.list<{ name: string; full_name: string }>(PERSON, ["name", "full_name"], [["user_tag", "in", ["Coordinator", "Admin"]]]),
  ]);
  const nm = new Map(names.map((x) => [x.name, x.full_name]));
  const who = new Map<string, { name: string; assigned: number; pending: number; calls: number; positive: number }>();
  const row = (id: string) => who.get(id) ?? (who.set(id, { name: nm.get(id) ?? (id ? id : "Earlier system (imported)"), assigned: 0, pending: 0, calls: 0, positive: 0 }), who.get(id)!);
  for (const r of asg) { const x = row(r.coordinator); x.assigned += r.n; if (r.status === PENDING) x.pending += r.n; }
  const byStatus = new Map<string, number>();
  for (const r of logs) {
    const x = row(r.coordinator); x.calls += r.n; if (POSITIVE.includes(r.status)) x.positive += r.n;
    byStatus.set(r.status, (byStatus.get(r.status) ?? 0) + r.n);
  }
  const list = [...who.values()];
  const sum = (k: "assigned" | "pending" | "calls" | "positive") => list.reduce((t, x) => t + x[k], 0);
  return c.json({
    period: weekly ? { weekly: true, from: wFrom, to: wTo } : null,
    totals: { assigned: sum("assigned"), calls: sum("calls"), positive: sum("positive"), pending: sum("pending") },
    by_status: [...byStatus].map(([label, value]) => ({ label, value })).sort((x, y) => y.value - x.value),
    by_coordinator: list.sort((x, y) => y.calls - x.calls),
  });
});



// ---------- event registrations (one record per person per event, for every festival / programme)
const REG_COLS = ["name", "event_code", "person", "person_name", "person_mob", "registration_no", "registered_at", "volunteer", "volunteer_slot", "service", "dinner", "donation", "transport_required", "standard"];
const flag = (v: unknown) => (v === true || v === 1 || v === "1" ? 1 : v === false || v === 0 || v === "0" ? 0 : undefined);
function regDetails(b: Body) {
  return {
    volunteer: flag(b.volunteer), volunteer_slot: clean(b.volunteer_slot, 60), service: clean(b.service, 80), dinner: flag(b.dinner),
    donation: pick(b.donation, DONATIONS), transport_required: flag(b.transport_required), standard: clean(b.standard, 40),
  };
}

/** Registers a person (by mobile) for an event. Doing it twice just updates the same record. */
app.post("/registrations", async (c) => {
  needStaff(c);
  const b = await body(c);
  const mob = normalizeMobile(b.mob);
  const event = clean(b.event, 60);
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  if (!(await loadEvents(c)).some((e) => e.code === event)) throw bad("Choose an event.");
  const erp = erpOf(c);
  const person = await getRow(erp, mob);
  if (!person) throw new HttpError(404, "This number is not registered yet. Register the person first.");
  c.set("log", { target: `${person.full_name} (${mob})` });
  const d = nonEmpty(regDetails(b));
  try {
    await erp.insert(REG, { event_code: event, person: person.name, registered_at: istNow(), ...d });
    c.executionCtx.waitUntil(notifyNewContact(c, person, event).catch((e) => console.error("whatsapp", e)));
    return c.json({ ok: true, created: true }, 201);
  } catch (e) {
    if (!isDuplicate(e)) throw e;
    if (Object.keys(d).length) await erp.update(REG, `${event}-${person.name}`, d);
    return c.json({ ok: true, created: false });
  }
});

const KINDS: Record<string, [string, string, unknown]> = {
  Volunteers: ["volunteer", "=", 1], Dinner: ["dinner", "=", 1], Donors: ["donation", "=", "Opted to Donate"], Transport: ["transport_required", "=", 1],
};
const regQuery = (q: Record<string, string>) => {
  const f: Filters = [];
  const event = clean(q.event, 60);
  if (event) f.push(["event_code", "=", event]);
  // Optional "kind" narrows the list to one group of registrations (used by the chips on the Registrations screen).
  const kind = KINDS[q.kind ?? ""];
  const text = clean(q.q, 60).replace(/[%_]/g, "");
  return { f, rowFilters: kind ? [...f, kind] : f, event, or: text ? { or_filters: [["person_name", "like", `%${text}%`], ["person_mob", "like", `%${text.replace(/\D/g, "") || text}%`]] } : {} };
};

app.get("/admin/registrations", async (c) => {
  needAdmin(c);
  const q = c.req.query();
  const { f, rowFilters, or } = regQuery(q);
  const page = Math.max(0, parseInt(q.page ?? "0", 10) || 0);
  const erp = erpOf(c);
  // The totals strip always describes the whole event (and search); the chip only narrows the rows below it.
  const [rows, total, volunteers, dinner, donors, transport] = await Promise.all([
    erp.list<Record<string, unknown>>(REG, REG_COLS, rowFilters, { ...or, order_by: "registered_at desc", limit_page_length: 50, limit_start: page * 50 }),
    erp.count(REG, f, or),
    erp.count(REG, [...f, ["volunteer", "=", 1]]),
    erp.count(REG, [...f, ["dinner", "=", 1]]),
    erp.count(REG, [...f, ["donation", "=", "Opted to Donate"]]),
    erp.count(REG, [...f, ["transport_required", "=", 1]]),
  ]);
  return c.json({ rows, page, page_size: 50, summary: { total, volunteers, dinner, donors, transport } });
});

app.get("/admin/export/registrations", async (c) => {
  needAdmin(c);
  const { rowFilters, or } = regQuery(c.req.query());
  const cols = REG_COLS.filter((x) => x !== "name");
  const rows = await erpOf(c).list<Record<string, unknown>>(REG, cols, rowFilters, { ...or, order_by: "registered_at desc", limit_page_length: 0 });
  return csvResponse(c, "folk-registrations.csv", csv(cols, rows));
});


// ---------- public registration links (no sign-in): the page, the number lookup and the submit
type LinkRow = {
  name: string; title: string; link_type: "Registration" | "Volunteer" | "Feedback"; event_code: string; assigned_to?: string; assigned_name?: string; is_open?: number; intro?: string;
  ask_dinner?: number; ask_transport?: number; ask_donation?: number; slot_options?: string; service_options?: string;
};
const LINK_FIELDS = ["name", "title", "link_type", "event_code", "assigned_to", "assigned_name", "is_open", "intro", "ask_dinner", "ask_transport", "ask_donation", "slot_options", "service_options"];
const lines = (s?: string) => (s ?? "").split("\n").map((x) => x.trim()).filter(Boolean);
const loadLink = (c: Ctx, slug: string) => cached(`link:${slug}`, 15_000, () => erpOf(c).get<LinkRow>(LINK, slug));
const GENDER_LABELS = [{ value: "M", label: "Male" }, { value: "F", label: "Female" }];

async function publicLimit(c: Ctx) {
  const ip = c.req.header("CF-Connecting-IP") ?? "unknown";
  const r = await c.env.PUBLIC_LIMITER?.limit({ key: `pub:${ip}` });
  if (r && !r.success) throw new HttpError(429, "Too many attempts. Please wait a minute and try again.");
}

/** Readable, stable link code for an event's own form, e.g. rathayatra-2026-feedback. Same rule as scripts/phase14_event_forms.py. */
const eventSlug = (code: string, kind: "register" | "feedback") => `${code.toLowerCase().replace(/[^a-z0-9]+/g, "-").slice(0, 24).replace(/^-+|-+$/g, "") || "event"}-${kind}`;

/** Creates the event's Registration and Feedback links if it has none. Safe to repeat. */
async function ensureEventLinks(erp: Erp, code: string, name: string) {
  const have = await erp.list<{ link_type: string }>(LINK, ["link_type"], [["event_code", "=", code]]);
  for (const [kind, type, label] of [["register", "Registration", "Registration"], ["feedback", "Feedback", "Feedback"]] as const) {
    if (have.some((h) => h.link_type === type)) continue;
    try { await erp.insert(LINK, { slug: eventSlug(code, kind), title: `${name} - ${label}`, link_type: type, event_code: code, is_open: 1 }); }
    catch (e) { if (!isDuplicate(e)) throw e; }
  }
}

app.get("/f/:slug", async (c) => {
  const nonce = crypto.randomUUID().replace(/-/g, "");
  const link = await loadLink(c, clean(c.req.param("slug"), 40));
  if (!link) return c.html(notFoundPage(nonce), 404, pageHeaders(nonce));
  const events = await loadEvents(c);
  const cfg: PageConfig = {
    slug: link.name, title: link.title, type: link.link_type, eventName: events.find((e) => e.code === link.event_code)?.name ?? link.event_code,
    open: !!link.is_open, intro: link.intro ?? "", asks: { dinner: !!link.ask_dinner, transport: !!link.ask_transport, donation: !!link.ask_donation },
    slots: lines(link.slot_options), services: lines(link.service_options), genders: GENDER_LABELS, occupations: [...OCCUPATIONS],
    colleges: (await loadOptions(c)).college.filter((o) => sameKey(o.title) !== sameKey(OTHERS)).map((o) => ({ value: o.id, label: o.title })),
    areas: (await loadOptions(c)).area.filter((o) => sameKey(o.title) !== sameKey(OTHERS)).map((o) => ({ value: o.id, label: o.title })),
  };
  return c.html(renderPage(cfg, nonce), 200, pageHeaders(nonce));
});

/** Only what the form shows is returned (never phone numbers, guide details, comments or call data). */
app.post("/pub/:slug/lookup", async (c) => {
  await publicLimit(c);
  const link = await loadLink(c, clean(c.req.param("slug"), 40));
  if (!link) throw new HttpError(404, "This link is not available.");
  if (!link.is_open) throw new HttpError(403, "This form is closed.");
  const mob = normalizeMobile((await body(c)).mob);
  if (!mob) throw bad("Please enter a valid 10-digit mobile number.");
  const erp = erpOf(c);
  const [p] = await erp.list<{ name: string; full_name: string; gender?: string; occupation?: string; profession?: string; venue?: string }>(
    PERSON, ["name", "full_name", "gender", "occupation", "college.title as profession", "area.title as venue"], [["mob_no", "=", mob]], { limit_page_length: 1 });
  if (!p) return c.json({ found: false });
  const reg = await erp.get(link.link_type === "Feedback" ? FB : REG, `${link.event_code}-${p.name}`);
  return c.json({ found: true, registered: !!reg, person: { name: p.full_name, gender: p.gender ?? "", occupation: p.occupation ?? "", profession: p.profession ?? "", venue: p.venue ?? "" } });
});

app.post("/pub/:slug/submit", async (c) => {
  await publicLimit(c);
  const slug = clean(c.req.param("slug"), 40);
  const link = await loadLink(c, slug);
  if (!link) throw new HttpError(404, "This link is not available.");
  if (!link.is_open) throw new HttpError(403, "This form is closed.");
  const b = await body(c);
  // Bots fill the hidden field or finish in under two seconds: pretend it worked, save nothing.
  if (clean(b.website) || (typeof b.waited === "number" && b.waited < 2000)) return c.json({ ok: true, name: "" });
  const mob = normalizeMobile(b.mob);
  if (!mob) throw bad("Please enter a valid 10-digit mobile number.");
  const erp = erpOf(c);

  if (link.link_type === "Feedback") return submitFeedback(c, erp, link, mob, b);

  // Questions for this link
  const reg: Record<string, unknown> = {};
  if (link.link_type === "Volunteer") {
    reg.volunteer = 1;
    const slots = lines(link.slot_options), services = lines(link.service_options);
    const slot = clean(b.slot, 60), service = clean(b.service, 60);
    if (slots.length && !slots.includes(slot)) throw bad("Please choose a time slot.");
    if (service && services.length && !services.includes(service)) throw bad("Please choose a service from the list.");
    if (slots.length) reg.volunteer_slot = slot;
    if (service) reg.service = service;
  } else {
    if (link.ask_dinner) reg.dinner = b.dinner === true ? 1 : 0;
    if (link.ask_transport) reg.transport_required = b.transport === true ? 1 : 0;
    if (link.ask_donation) reg.donation = b.donation === true ? "Opted to Donate" : "Pending";
  }

  // The person: existing details are never changed from this page.
  let [person] = await erp.list<Row>(PERSON, AUTH_FIELDS, [["mob_no", "=", mob]], { limit_page_length: 1 });
  let created = false;
  if (!person) {
    const name = clean(b.name, 100);
    const gender = pick(b.gender, GENDERS);
    if (!name) throw bad("Please enter your name.");
    if (!gender) throw bad("Please choose your gender.");
    const doc = {
      mob_no: mob, full_name: name, gender, occupation: pick(b.occupation, OCCUPATIONS), college: (await publicCollege(c, b)) || undefined, area: (await publicArea(c, b)) || undefined,
      event_code: link.event_code, user_tag: "Public", is_active: 1, registered_on: istToday(), registered_by: `Link: ${link.title}`.slice(0, 140),
    };
    try {
      person = (await erp.insert<Row>(PERSON, nonEmpty(doc))).data;
      created = true;
    } catch (e) {
      if (!isDuplicate(e)) throw e;
      [person] = await erp.list<Row>(PERSON, AUTH_FIELDS, [["mob_no", "=", mob]], { limit_page_length: 1 });
    }
  }
  if (!person) throw new HttpError(500, "Could not save. Please try again.");

  const id = `${link.event_code}-${person.name}`;
  let already = false;
  try {
    await erp.insert(REG, { event_code: link.event_code, person: person.name, registered_at: istNow(), via_link: slug, ...(link.assigned_to && { referred_by: link.assigned_to }), ...reg });
  } catch (e) {
    if (!isDuplicate(e)) throw e;
    already = true;
    if (Object.keys(reg).length) await erp.update(REG, id, reg);
  }
  // Welcome on a fresh registration only (new or existing contact); re-submitting the form sends nothing.
  if (!already) { const who = person; c.executionCtx.waitUntil(notifyNewContact(c, who, link.event_code).catch((e) => console.error("whatsapp", e))); }
  c.set("actor", { id: person.name, mob, name: person.full_name, tag: "Public link" });
  c.set("log", { target: `${person.full_name} (${mob})`, details: `${link.title}${created ? " · new contact" : ""}${already ? " · updated" : ""}` });
  return c.json({ ok: true, name: person.full_name, created, already });
});

/** A feedback form answer: one per person per event (sending again replaces the earlier answer). */
async function submitFeedback(c: Ctx, erp: Erp, link: LinkRow, mob: string, b: Body) {
  const rating = intIn(b.rating, 1, 5);
  if (!rating) throw bad("Please choose a rating from 1 to 5.");
  let [person] = await erp.list<Row>(PERSON, AUTH_FIELDS, [["mob_no", "=", mob]], { limit_page_length: 1 });
  let created = false;
  if (!person) {
    const name = clean(b.name, 100);
    if (!name) throw bad("Please enter your name.");
    const doc = { mob_no: mob, full_name: name, gender: pick(b.gender, GENDERS), event_code: link.event_code, user_tag: "Public", is_active: 1, registered_on: istToday(), registered_by: `Link: ${link.title}`.slice(0, 140) };
    try { person = (await erp.insert<Row>(PERSON, nonEmpty(doc))).data; created = true; }
    catch (e) { if (!isDuplicate(e)) throw e; [person] = await erp.list<Row>(PERSON, AUTH_FIELDS, [["mob_no", "=", mob]], { limit_page_length: 1 }); }
  }
  if (!person) throw new HttpError(500, "Could not save. Please try again.");
  const key = `${link.event_code}-${person.name}`;
  const answer = { rating, liked: clean(b.liked, 500), improve: clean(b.improve, 500), comments: clean(b.comments, 500) };
  let already = false;
  try { await erp.insert(FB, { fb_key: key, event_code: link.event_code, person: person.name, via_link: link.name, submitted_at: istNow(), ...answer }); }
  catch (e) { if (!isDuplicate(e)) throw e; already = true; await erp.update(FB, key, { ...answer, via_link: link.name, submitted_at: istNow() }); }
  c.set("actor", { id: person.name, mob, name: person.full_name, tag: "Public link" });
  c.set("log", { target: `${person.full_name} (${mob})`, details: `${link.title} · ${rating}/5${created ? " · new contact" : ""}${already ? " · updated" : ""}` });
  return c.json({ ok: true, name: person.full_name, created, already });
}

/** Feedback answers for an event (admin). */
const FB_COLS = ["name", "event_code", "person_name", "person_mob", "rating", "liked", "improve", "comments", "submitted_at"];
const fbQuery = (q: Record<string, string>) => {
  const f: Filters = [];
  const event = clean(q.event, 60);
  if (event) f.push(["event_code", "=", event]);
  const text = clean(q.q, 60).replace(/[%_]/g, "");
  return { f, or: text ? { or_filters: [["person_name", "like", `%${text}%`], ["person_mob", "like", `%${text.replace(/\D/g, "") || text}%`]] } : {} };
};
app.get("/admin/feedback", async (c) => {
  needAdmin(c);
  const q = c.req.query();
  const { f, or } = fbQuery(q);
  const page = Math.max(0, parseInt(q.page ?? "0", 10) || 0);
  const erp = erpOf(c);
  const [rows, total, stars] = await Promise.all([
    erp.list<Record<string, unknown>>(FB, FB_COLS, f, { ...or, order_by: "submitted_at desc", limit_page_length: 50, limit_start: page * 50 }),
    erp.count(FB, f, or),
    erp.list<{ rating: number; n: number }>(FB, aggregate("rating", { COUNT: "*", as: "n" }), f, { ...or, group_by: "rating", limit_page_length: 10 }),
  ]);
  const answered = stars.reduce((a, x) => a + x.n, 0);
  const average = answered ? Math.round((stars.reduce((a, x) => a + x.rating * x.n, 0) / answered) * 10) / 10 : 0;
  return c.json({ rows, page, page_size: 50, summary: { total, average } });
});
app.get("/admin/export/feedback", async (c) => {
  needAdmin(c);
  const { f, or } = fbQuery(c.req.query());
  const cols = FB_COLS.filter((x) => x !== "name");
  const rows = await erpOf(c).list<Record<string, unknown>>(FB, cols, f, { ...or, order_by: "submitted_at desc", limit_page_length: 0 });
  return csvResponse(c, "folk-feedback.csv", csv(cols, rows));
});

// ---------- registration links: admin manages them, staff see the ones assigned to them
const SLUG_CHARS = "abcdefghjkmnpqrstuvwxyz23456789";
const newSlug = () => Array.from(crypto.getRandomValues(new Uint8Array(8)), (n) => SLUG_CHARS[n % SLUG_CHARS.length]).join("");

async function linksOut(c: Ctx, rows: LinkRow[]) {
  const [events, regCounts, fbCounts] = await Promise.all([
    loadEvents(c),
    erpOf(c).list<{ via_link: string; n: number }>(REG, aggregate({ COUNT: "*", as: "n" }, "via_link"), [["via_link", "!=", ""]], { group_by: "via_link", limit_page_length: 0 }),
    erpOf(c).list<{ via_link: string; n: number }>(FB, aggregate({ COUNT: "*", as: "n" }, "via_link"), [["via_link", "!=", ""]], { group_by: "via_link", limit_page_length: 0 }),
  ]);
  const counts = [...regCounts, ...fbCounts];
  const origin = new URL(c.req.url).origin;
  const n = new Map(counts.map((x) => [x.via_link, x.n]));
  return rows.map((l) => ({
    slug: l.name, title: l.title, type: l.link_type, event_code: l.event_code, event_name: events.find((e) => e.code === l.event_code)?.name ?? l.event_code,
    assigned_to: l.assigned_to ?? "", assigned_name: l.assigned_name ?? "", is_open: !!l.is_open, intro: l.intro ?? "",
    ask_dinner: !!l.ask_dinner, ask_transport: !!l.ask_transport, ask_donation: !!l.ask_donation,
    slots: lines(l.slot_options), services: lines(l.service_options), url: `${origin}/f/${l.name}`, count: n.get(l.name) ?? 0,
  }));
}

/** Validates the fields an admin may set. Only keys that were sent are returned, so a partial edit changes nothing else. */
async function linkPatch(c: Ctx, b: Body): Promise<Record<string, unknown>> {
  const p: Record<string, unknown> = {};
  if ("title" in b) { const t = clean(b.title, 80); if (!t) throw bad("Enter a title."); p.title = t; }
  if ("intro" in b) p.intro = clean(b.intro, 400);
  if (typeof b.is_open === "boolean") p.is_open = b.is_open ? 1 : 0;
  for (const k of ["ask_dinner", "ask_transport", "ask_donation"] as const) if (typeof b[k] === "boolean") p[k] = b[k] ? 1 : 0;
  const list = (v: unknown) => (Array.isArray(v) ? [...new Set(v.map((x) => clean(x, 60)).filter(Boolean))].slice(0, 20).join("\n") : undefined);
  if ("slots" in b) p.slot_options = list(b.slots) ?? "";
  if ("services" in b) p.service_options = list(b.services) ?? "";
  if ("assigned_mob" in b) {
    const raw = String(b.assigned_mob ?? "").trim();
    if (!raw) p.assigned_to = null;
    else {
      const mob = normalizeMobile(raw);
      if (!mob) throw bad("Enter a valid 10-digit mobile number for the person this link is assigned to.");
      const row = await getRow(erpOf(c), mob);
      if (!row) throw new HttpError(404, "That mobile number is not in the list of people.");
      p.assigned_to = row.name;
    }
  }
  return p;
}

app.get("/admin/links", async (c) => {
  needAdmin(c);
  const rows = await erpOf(c).list<LinkRow>(LINK, LINK_FIELDS, [], { order_by: "creation desc", limit_page_length: 200 });
  return c.json({ links: await linksOut(c, rows) });
});

app.post("/admin/links", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const type = pick(b.type, ["Registration", "Volunteer"] as const);
  const event = clean(b.event, 60);
  if (!type) throw bad("Choose the type of link.");
  if (!(await loadEvents(c)).some((e) => e.code === event && !e.is_list)) throw bad("Choose an event.");
  if (!clean(b.title, 80)) throw bad("Enter a title.");
  const patch = await linkPatch(c, b);
  const erp = erpOf(c);
  for (let i = 0; i < 5; i++) {
    const slug = newSlug();
    try {
      const r = await erp.insert<LinkRow>(LINK, { slug, link_type: type, event_code: event, is_open: 1, ...patch });
      return c.json({ link: (await linksOut(c, [r.data]))[0] }, 201);
    } catch (e) { if (!isDuplicate(e)) throw e; }
  }
  throw new HttpError(500, "Could not create the link. Please try again.");
});

app.patch("/admin/links/:slug", async (c) => {
  needAdmin(c);
  const slug = clean(c.req.param("slug"), 40);
  const erp = erpOf(c);
  if (!(await erp.get<LinkRow>(LINK, slug))) throw new HttpError(404, "Link not found.");
  const patch = await linkPatch(c, await body(c));
  if (Object.keys(patch).length) await erp.update(LINK, slug, patch);
  memo.delete(`link:${slug}`);
  return c.json({ link: (await linksOut(c, [(await erp.get<LinkRow>(LINK, slug))!]))[0] });
});

/** Links assigned to the signed-in coordinator or admin, ready to share. */
app.get("/my/links", async (c) => {
  needStaff(c);
  const rows = await erpOf(c).list<LinkRow>(LINK, LINK_FIELDS, [["assigned_to", "=", c.get("session").id]], { order_by: "creation desc", limit_page_length: 50 });
  return c.json({ links: await linksOut(c, rows) });
});

// ---------- admin: activity log
const LOG_FIELDS = ["at", "user_name", "role", "action", "target", "details"];
const logQuery = (q: Record<string, string>) => {
  const f: Filters = [];
  if (clean(q.role, 20)) f.push(["role", "=", clean(q.role, 20)]);
  if (DATE_RE.test(q.from ?? "")) f.push(["at", ">=", `${q.from} 00:00:00`]);
  if (DATE_RE.test(q.to ?? "")) f.push(["at", "<=", `${q.to} 23:59:59`]);
  const text = clean(q.q, 60).replace(/[%_]/g, "");
  return { f, or: text ? { or_filters: [["user_name", "like", `%${text}%`], ["action", "like", `%${text}%`], ["target", "like", `%${text}%`], ["details", "like", `%${text}%`]] } : {} };
};

app.get("/admin/logs", async (c) => {
  needAdmin(c);
  const q = c.req.query();
  const { f, or } = logQuery(q);
  const page = Math.max(0, parseInt(q.page ?? "0", 10) || 0);
  const erp = erpOf(c);
  const [rows, total] = await Promise.all([
    erp.list<Record<string, string>>(ACT, LOG_FIELDS, f, { ...or, order_by: "at desc", limit_page_length: 50, limit_start: page * 50 }),
    erp.count(ACT, f, or),
  ]);
  return c.json({ rows, total, page, page_size: 50 });
});

app.get("/admin/export/logs", async (c) => {
  needAdmin(c);
  const { f, or } = logQuery(c.req.query());
  const rows = await erpOf(c).list<Record<string, unknown>>(ACT, LOG_FIELDS, f, { ...or, order_by: "at desc", limit_page_length: 0 });
  return csvResponse(c, "folk-activity-log.csv", csv(LOG_FIELDS, rows));
});

// ---------- admin: reception (attendance) list, exports
const rangeFilters = (q: Record<string, string>, tsField: string, eventField = "event_code"): Filters => {
  const f: Filters = [];
  const event = clean(q.event, 60);
  if (event) f.push([eventField, "=", event]);
  if (DATE_RE.test(q.from ?? "")) f.push([tsField, ">=", `${q.from} 00:00:00`]);
  if (DATE_RE.test(q.to ?? "")) f.push([tsField, "<=", `${q.to} 23:59:59`]);
  return f;
};
const ATT_COLS = ["ts", "person_name", "person_mob", "event_code", "marked_by_name"];

/** Reception view: who attended in a date range, with call totals for the same range. */
app.get("/admin/attendance", async (c) => {
  needAdmin(c);
  const q = c.req.query();
  const erp = erpOf(c);
  const f = rangeFilters(q, "ts");
  const text = clean(q.q, 60);
  const search = text ? { or_filters: [["person_name", "like", `%${text}%`], ["person_mob", "like", `%${text.replace(/\D/g, "") || text}%`]] } : {};
  const page = Math.max(0, parseInt(q.page ?? "0", 10) || 0);
  const lf = rangeFilters(q, "called_at");
  const [checkins, perPerson, rows, calls, people] = await Promise.all([
    erp.count(ATT, f),
    erp.list<{ person: string; n: number }>(ATT, aggregate({ COUNT: "*", as: "n" }, "person"), f, { group_by: "person", limit_page_length: 0 }),
    erp.list<Record<string, string>>(ATT, ["name", ...ATT_COLS], f, { ...search, order_by: "ts desc", limit_page_length: 100, limit_start: page * 100 }),
    erp.list<{ status: string; n: number }>(LOG, aggregate({ COUNT: "*", as: "n" }, "status"), lf, { group_by: "status", limit_page_length: 0 }),
    erp.count(PERSON, [["user_tag", "in", CONTACT_TAGS]]),
  ]);
  const made = calls.reduce((t, x) => t + x.n, 0);
  const positive = calls.filter((x) => POSITIVE.includes(x.status)).reduce((t, x) => t + x.n, 0);
  return c.json({ summary: { contacts: people, checkins, people: perPerson.length, calls: made, positive }, rows, page, page_size: 100 });
});

app.get("/admin/export/attendance", async (c) => {
  needAdmin(c);
  const rows = await erpOf(c).list<Record<string, unknown>>(ATT, ATT_COLS, rangeFilters(c.req.query(), "ts"), { order_by: "ts desc", limit_page_length: 0 });
  return csvResponse(c, "folk-attendance.csv", csv(ATT_COLS, rows));
});

const ASG_COLS = ["person_name", "person_mob", "coordinator_name", "event_code", "status", "note", "is_follow_up", "assigned_at", "submitted_at"];
app.get("/admin/export/assignments", async (c) => {
  needAdmin(c);
  const rows = await erpOf(c).list<Record<string, unknown>>(ASG, ASG_COLS, rangeFilters(c.req.query(), "assigned_at"), { order_by: "assigned_at desc", limit_page_length: 0 });
  return csvResponse(c, "folk-assigned-calls.csv", csv(ASG_COLS, rows));
});

const LOG_COLS = ["called_at", "person_name", "person_mob", "coordinator_name", "legacy_caller", "event_code", "status", "note"];
app.get("/admin/export/calls", async (c) => {
  needAdmin(c);
  const rows = await erpOf(c).list<Record<string, unknown>>(LOG, LOG_COLS, rangeFilters(c.req.query(), "called_at"), { order_by: "called_at desc", limit_page_length: 0 });
  return csvResponse(c, "folk-calls.csv", csv(LOG_COLS, rows));
});

// ---------- admin: import contacts from a Google Form's response sheet (or a CSV file)
const IMPORT_BATCH = 100; // rows saved per request: keeps every request small and fast
const IMPORT_PERSON_FIELDS = ["name", "mob_no", "full_name", "gender", "level", "occupation", "college.title as profession", "pg.title as pg_name", "area.title as venue", "guide.title as guide", "event_code", "user_tag"];
const ROW_TO_DOC: Record<string, keyof ImportRow> = {
  full_name: "name", gender: "gender", level: "level", occupation: "occupation", profession: "profession", pg_name: "pg_name", venue: "venue",
  guide: "guide", event_code: "event_code",
};

async function importTable(b: Record<string, unknown>): Promise<string[][]> {
  let text = typeof b.csv === "string" ? b.csv : "";
  if (!text) {
    const link = clean(b.url, 600);
    if (!link) throw bad("Paste a Google Sheets link or choose a file.");
    try { text = await loadSheetCsv(link); } catch (e) { if (e instanceof ImportError) throw bad(e.message); throw e; }
  }
  if (text.length > MAX_IMPORT_BYTES) throw bad("That file is too large. Import it in smaller parts.");
  const table = parseCsv(text);
  if (table.length < 2) throw bad("The sheet has a header but no data rows.");
  if (table.length - 1 > MAX_IMPORT_ROWS) throw bad(`Too many rows (${table.length - 1}). Import at most ${MAX_IMPORT_ROWS} at a time.`);
  return table;
}

function mappingOf(b: Record<string, unknown>, columns: number): Mapping {
  const raw = (b.mapping && typeof b.mapping === "object" ? b.mapping : {}) as Record<string, unknown>;
  const m: Mapping = {};
  for (const f of IMPORT_FIELDS) {
    const v = raw[f];
    if (typeof v === "number" && Number.isInteger(v) && v >= 0 && v < columns) m[f] = v;
  }
  if (m.mob === undefined || m.name === undefined) throw bad("Choose which column is the mobile number and which is the name.");
  return m;
}

async function importPlan(c: Ctx, b: Record<string, unknown>) {
  const table = await importTable(b);
  const map = mappingOf(b, table[0].length);
  const events = await loadEvents(c);
  const byKey = new Map<string, string>();
  for (const e of events) { byKey.set(e.code.toLowerCase(), e.code); byKey.set(e.name.toLowerCase(), e.code); }
  const defaultEvent = byKey.get(clean(b.event_code, 60).toLowerCase()) ?? "";
  const guides = (await loadOptions(c)).guide;
  const built = buildRows(table, map, {
    defaultLevel: pick(b.default_level, LEVELS) || "Folk Foundation",
    normalizeMobile,
    knownEvent: (v) => byKey.get(v.toLowerCase()) ?? defaultEvent,
    knownGuide: (v) => findTitle(guides, v)?.title ?? "",
  });
  return { table, map, built };
}

type Existing = Record<string, string | number | null>;
async function existingByMob(erp: Erp, mobs: string[]): Promise<Map<string, Existing>> {
  const out = new Map<string, Existing>();
  const parts = chunk(mobs, 200);
  const lists = await Promise.all(parts.map((ch) => erp.list<Existing>(PERSON, IMPORT_PERSON_FIELDS, [["mob_no", "in", ch]], { limit_page_length: 0 })));
  for (const r of lists.flat()) out.set(String(r.mob_no), r);
  return out;
}

/** What importing [row] over [old] would change. policy: "fill" only fills empty fields, "overwrite" replaces with the sheet's non-empty values. */
function changesFor(old: Existing, row: ImportRow, policy: "fill" | "overwrite") {
  const out: { field: string; from: string; to: string }[] = [];
  for (const [col, key] of Object.entries(ROW_TO_DOC)) {
    const next = String(row[key] ?? "");
    const cur = String(old[col] ?? "");
    if (!next || next === cur) continue;
    if (policy === "fill" && cur) continue;
    out.push({ field: col, from: cur, to: next });
  }
  return out;
}

app.post("/admin/import/preview", async (c) => {
  needAdmin(c);
  const table = await importTable(await body(c));
  return c.json({ headers: table[0].map((h) => h.trim()), sample: table.slice(1, 4), total_rows: table.length - 1, mapping: guessMapping(table[0]) });
});

app.post("/admin/import/check", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const { built } = await importPlan(c, b);
  const old = await existingByMob(erpOf(c), built.rows.map((r) => r.mob));
  const fresh = built.rows.filter((r) => !old.has(r.mob));
  const there = built.rows.filter((r) => old.has(r.mob));
  const diffs = there.map((r) => ({ r, o: old.get(r.mob)!, ch: changesFor(old.get(r.mob)!, r, "overwrite") })).filter((x) => x.ch.length);
  return c.json({
    valid: built.rows.length, new: fresh.length, existing: there.length, existing_with_changes: diffs.length,
    invalid: built.invalid.length, duplicates_in_sheet: built.duplicatesInSheet,
    new_sample: fresh.slice(0, 50).map((r) => ({ line: r.line, mob: r.mob, name: r.name, level: r.level, gender: r.gender })),
    existing_sample: diffs.slice(0, 30).map((x) => ({ mob: x.r.mob, name: String(x.o.full_name ?? ""), role: String(x.o.user_tag ?? ""), changes: x.ch })),
    invalid_sample: built.invalid.slice(0, 30),
  });
});

/** Saves one batch (rows offset..offset+100). The app calls it again with next_offset until it is null. */
app.post("/admin/import/commit", async (c) => {
  needAdmin(c);
  const s = c.get("session");
  const b = await body(c);
  const policy = pick(b.existing_policy, ["skip", "fill", "overwrite"] as const) || "skip";
  const offset = Math.max(0, parseInt(String(b.offset ?? "0"), 10) || 0);
  const { built } = await importPlan(c, b);
  const erp = erpOf(c);
  const batch = built.rows.slice(offset, offset + IMPORT_BATCH);
  const old = await existingByMob(erp, batch.map((r) => r.mob));
  const result = { added: 0, updated: 0, skipped: 0, failed: 0 };

  // College / Company is stored by ID: each typed name is matched to the list (or added) once per batch.
  const collegeOf = new Map<string, string>();
  for (const t of new Set(batch.map((r) => r.profession).filter(Boolean))) collegeOf.set(t, await optionId(c, "college", t));
  const pgOf = new Map<string, string>();
  for (const t of new Set(batch.map((r) => r.pg_name).filter(Boolean))) pgOf.set(t, await optionId(c, "pg", t));
  const areaOf = new Map<string, string>();
  for (const t of new Set(batch.map((r) => r.venue).filter(Boolean))) areaOf.set(t, await optionId(c, "area", t));
  const guideId = new Map((await loadOptions(c)).guide.map((g) => [g.title, g.id]));
  const toDoc = (field: string, v: string): [string, unknown] =>
    field === "profession" ? ["college", collegeOf.get(v) || null] : field === "pg_name" ? ["pg", pgOf.get(v) || null] : field === "venue" ? ["area", areaOf.get(v) || null] : field === "guide" ? ["guide", guideId.get(v) || null] : [field, v];
  const fresh = batch.filter((r) => !old.has(r.mob));
  const docs = fresh.map((r) => ({
    doctype: PERSON, mob_no: r.mob, full_name: r.name, gender: r.gender, level: r.level, occupation: r.occupation, college: collegeOf.get(r.profession) || undefined, pg: pgOf.get(r.pg_name) || undefined,
    ...(areaOf.get(r.venue) && { area: areaOf.get(r.venue) }), ...(guideId.get(r.guide) && { guide: guideId.get(r.guide) }), ...(r.event_code && { event_code: r.event_code }),
    user_tag: "Public", is_active: 1, registered_by: `Import (${s.name})`, registered_on: istToday(),
  }));
  if (docs.length) {
    try { await erp.call("POST", "/api/method/frappe.client.insert_many", { docs }); result.added += docs.length; }
    catch {
      // One bad row must not sink the batch: retry one by one, skipping numbers that appeared meanwhile.
      for (const d of docs) {
        try { await erp.insert(PERSON, d); result.added++; } catch (e) { if (isDuplicate(e)) result.skipped++; else result.failed++; }
      }
    }
  }

  const there = batch.filter((r) => old.has(r.mob));
  if (policy === "skip") result.skipped += there.length;
  else {
    const edits: Record<string, unknown>[] = [];
    for (const r of there) {
      const o = old.get(r.mob)!;
      if (o.user_tag && !CONTACT_TAGS.includes(String(o.user_tag))) { result.skipped++; continue; } // never change staff accounts through an import
      const ch = changesFor(o, r, policy);
      if (!ch.length) { result.skipped++; continue; }
      edits.push({ doctype: PERSON, docname: String(o.name), ...Object.fromEntries(ch.map((x) => toDoc(x.field, x.to))) });
    }
    if (edits.length) {
      try { const r = await erp.call("POST", "/api/method/frappe.client.bulk_update", { docs: JSON.stringify(edits) }); // Frappe expects the list as text
      const failed = (r?.message?.failed_docs as unknown[] | undefined)?.length ?? 0;
      result.updated += edits.length - failed; result.failed += failed; }
      catch { result.failed += edits.length; }
    }
  }
  memo.clear();
  const next = offset + IMPORT_BATCH;
  return c.json({ ...result, next_offset: next < built.rows.length ? next : null, total: built.rows.length, invalid: built.invalid.length });
});

// Saved sources: remembered sheet + column mapping, so "check for new entries" is one tap next time.
type ImportSource = { id: string; name: string; url: string; mapping: Mapping; default_level: string; event_code: string };
async function loadSources(c: Ctx): Promise<ImportSource[]> {
  const r = await erpOf(c).get<{ import_sources?: string }>("FOLK Settings", "FOLK Settings");
  try { const v = JSON.parse(r?.import_sources || "[]"); return Array.isArray(v) ? (v as ImportSource[]) : []; } catch { return []; }
}
app.get("/admin/import/sources", async (c) => { needAdmin(c); return c.json({ sources: await loadSources(c) }); });
app.put("/admin/import/sources", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const raw = Array.isArray(b.sources) ? (b.sources as Record<string, unknown>[]) : [];
  if (raw.length > 20) throw bad("Too many saved sources.");
  const list: ImportSource[] = raw.map((x, i) => {
    const m: Mapping = {};
    for (const f of IMPORT_FIELDS) { const v = (x.mapping as Record<string, unknown> | undefined)?.[f]; if (typeof v === "number" && Number.isInteger(v) && v >= 0 && v < 200) m[f as ImportField] = v; }
    return { id: clean(x.id, 20) || `s${Date.now()}${i}`, name: clean(x.name, 60) || "Form", url: clean(x.url, 600), mapping: m, default_level: pick(x.default_level, LEVELS) || "Folk Foundation", event_code: clean(x.event_code, 60) };
  }).filter((x) => x.url);
  await erpOf(c).update("FOLK Settings", "FOLK Settings", { import_sources: JSON.stringify(list) });
  return c.json({ sources: list });
});

// ---------- admin: WhatsApp message templates for the Send Message button
app.get("/admin/templates", async (c) => { needAdmin(c); memo.delete("templates"); return c.json({ templates: await loadTemplates(c) }); });
app.put("/admin/templates", async (c) => {
  needAdmin(c);
  const b = await body(c);
  const raw = Array.isArray(b.templates) ? (b.templates as Record<string, unknown>[]) : [];
  if (raw.length > 20) throw bad("Too many templates.");
  const list: Template[] = raw.map((t, i) => ({ id: clean(t.id, 20) || `t${Date.now()}${i}`, heading: clean(t.heading, 60) || "Message", text: clean(t.text, 1000), active: t.active === true })).filter((t) => t.text);
  if (list.length && !list.some((t) => t.active)) list[0].active = true;
  let seen = false;
  for (const t of list) { if (t.active && seen) t.active = false; if (t.active) seen = true; }
  await erpOf(c).update("FOLK Settings", "FOLK Settings", { message_templates: JSON.stringify(list) });
  memo.delete("templates");
  return c.json({ templates: list });
});

// ---------- phone notifications: the app registers its Firebase token after sign-in and removes it on sign-out
app.post("/devices", async (c) => {
  staffOnly(c);
  const s = c.get("session");
  const token = clean((await body(c)).token, 400);
  if (token.length < 20) throw bad("Invalid token.");
  const erp = erpOf(c);
  const key = token.slice(0, 140);
  const [have] = await erp.list<{ name: string; person: string }>(DEVICE, ["name", "person"], [["token_key", "=", key]], { limit_page_length: 1 });
  if (have) { if (have.person !== s.id) await erp.update(DEVICE, have.name, { person: s.id, token }); }
  else {
    try { await erp.insert(DEVICE, { token, token_key: key, person: s.id, platform: "android" }); }
    catch (e) { if (!isDuplicate(e)) throw e; }
  }
  return c.json({ ok: true });
});
app.post("/devices/remove", async (c) => {
  const s = c.get("session");
  const token = clean((await body(c)).token, 400);
  const erp = erpOf(c);
  for (const d of await erp.list<{ name: string }>(DEVICE, ["name"], [["token_key", "=", token.slice(0, 140)], ["person", "=", s.id]])) await erp.remove(DEVICE, d.name);
  return c.json({ ok: true });
});

// ---------- receipt printing: any phone sends a receipt to the shared queue; a phone connected to the printer prints it (see printHub.ts)
export { PrintHub } from "./printHub";
const hubOf = (env: Bindings) => env.PRINT_HUB.get(env.PRINT_HUB.idFromName("main"));

app.post("/print/jobs", async (c) => {
  staffOnly(c);
  const s = c.get("session");
  const b = await body(c);
  const key = clean(b.key, 64);
  const mob = normalizeMobile(b.mob);
  if (key.length < 8) throw bad("Invalid request.");
  if (!mob) throw bad("Enter a valid 10-digit mobile number.");
  const ts = typeof b.ts === "string" && TS_RE.test(b.ts) ? b.ts : istNow();
  const count = Math.min(Math.max(Math.floor(Number(b.count)) || 0, 0), 9999);
  const guide = await guideOf(c, (await getRow(erpOf(c), mob))?.guide); // the receipt can print the FOLK guide's name and phone
  const data = { name: clean(b.name), mob, event: clean(b.event, 100), ts, count, marked_by: s.name, guide: guide?.title ?? "", guide_mobile: guide?.mobile ?? "" };
  const r = await hubOf(c.env).fetch("https://hub/enqueue", { method: "POST", body: JSON.stringify({ key, data }) });
  return c.json({ queued: true, ...((await r.json()) as { stations: number }) });
});

/** How many phones are connected to a printer right now (the app shows it next to "Mark & Print Receipt"). */
app.get("/print/status", async (c) => {
  staffOnly(c);
  const r = await hubOf(c.env).fetch("https://hub/status");
  return c.json((await r.json()) as { stations: number });
});

/** The station connection is a WebSocket, so it is answered here (before the normal routes) after checking the sign-in. */
async function stationSocket(req: Request, env: Bindings): Promise<Response> {
  const h = req.headers.get("Authorization") ?? "";
  const payload = h.startsWith("Bearer ") ? await verifyToken(h.slice(7), env.JWT_SECRET) : null;
  if (!payload || typeof payload.sub !== "string" || payload.purpose) return new Response("Please sign in again.", { status: 401 });
  const row = await getById(new Erp(env), payload.sub);
  if (!row || row.is_active === 0 || !isStaffRow(row)) return new Response("Not allowed.", { status: 403 });
  return hubOf(env).fetch(new Request("https://hub/station", req));
}


/**
 * Friday 6:30 pm India time (cron 13:00 UTC): if no contacts were assigned today, remind every admin to assign calls.
 * Calls are made and assigned on Fridays, so one reminder per Friday is all that is needed.
 */
async function fridayReminder(env: Bindings) {
  const erp = new Erp(env);
  const today = istToday();
  const done = await erp.count(ASG, [["assigned_at", ">=", `${today} 00:00:00`]]);
  if (done > 0) return;
  const admins = await erp.list<{ name: string }>(PERSON, ["name"], [["user_tag", "=", "Admin"], ["is_active", "=", 1]]);
  await pushTo(env, erp, admins.map((a) => a.name), "Assign calls", "No contacts have been assigned for calling today. Please assign them now.", { route: "/admin" });
}

export default {
  fetch(req: Request, env: Bindings, ctx: ExecutionContext): Response | Promise<Response> {
    if (req.headers.get("Upgrade") === "websocket" && new URL(req.url).pathname === "/print/station") return stationSocket(req, env);
    return app.fetch(req, env, ctx);
  },
  scheduled(_e: ScheduledController, env: Bindings, ctx: ExecutionContext) {
    ctx.waitUntil(fridayReminder(env).catch((e) => console.error("fridayReminder", e)));
  },
};
