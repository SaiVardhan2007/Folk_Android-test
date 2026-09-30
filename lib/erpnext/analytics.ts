// Admin analytics: everything is computed from FOLK Users (people) and their attendance child rows.
// Fine for thousands of people; if it ever grows past that, move the grouping into an ERPNext report.
import { LEVELS } from "@/lib/levels";
import { TAGS } from "@/lib/roles";
import { erp, list, qs } from "./client";

export type AnalyticsFilters = { from: string; to: string; event: string; level: string; gender: string };

type P = {
  mob_no: string; full_name: string; gender?: string; level?: string; pg_name?: string; profession?: string;
  event_code?: string; user_tag?: string; registered_by?: string; creation: string;
};
type A = { parent: string; event_code: string; attendance_date: string; marked_by: string };

export type Row = { key: string; people: number; attended: number; checkins: number };
export type Count = { label: string; value: number; hint?: string };

export type Analytics = {
  kpi: { people: number; newRegistrations: number; attended: number; checkins: number; rate: number; notAttended: number };
  byLevel: Row[]; byGender: Row[]; byTag: Row[]; byEvent: Row[];
  frequency: Count[]; weekday: Count[]; topAttendees: Count[];
  topPg: Count[]; topProfession: Count[]; byVolunteer: Count[]; byRegistrar: Count[];
};

const day = (s: string) => s.slice(0, 10);
const weekdayOf = (s: string) => new Date(s + "T00:00:00Z").getUTCDay(); // 0 = Sunday
const NONE = "(not set)";
const clean = (v?: string) => (v ?? "").trim();

const group = <T,>(items: T[], key: (t: T) => string) => {
  const m = new Map<string, T[]>();
  for (const i of items) { const k = key(i); (m.get(k) ?? m.set(k, []).get(k)!).push(i); }
  return m;
};
const top = (m: Map<string, unknown[]>, n = 8): Count[] =>
  [...m].map(([label, v]) => ({ label, value: v.length })).sort((a, b) => b.value - a.value || a.label.localeCompare(b.label)).slice(0, n);

/** Groups people by a key and adds the unique-attendee and check-in counts for each group (one pass over the check-ins). */
function breakdown(people: P[], rows: A[], key: (p: P) => string, order: readonly string[]): Row[] {
  const byMob = new Map(people.map((p) => [p.mob_no, p]));
  const groups = group(people, key);
  const visits = new Map<string, { who: Set<string>; checkins: number }>();
  for (const r of rows) {
    const person = byMob.get(r.parent);
    if (!person) continue;
    const k = key(person);
    const v = visits.get(k) ?? visits.set(k, { who: new Set(), checkins: 0 }).get(k)!;
    v.who.add(r.parent);
    v.checkins++;
  }
  return [...new Set([...order, ...groups.keys()])]
    .map((k) => ({ key: k, people: groups.get(k)?.length ?? 0, attended: visits.get(k)?.who.size ?? 0, checkins: visits.get(k)?.checkins ?? 0 }))
    .filter((r) => r.people || r.checkins);
}

/** Most common values of a free-text field (case-insensitive), shown with the first spelling seen. */
function topText(people: P[], field: "pg_name" | "profession"): Count[] {
  const withValue = people.filter((p) => clean(p[field]));
  const groups = group(withValue, (p) => clean(p[field]).toLowerCase());
  return top(groups).map((c) => ({ ...c, label: clean(groups.get(c.label)![0][field]) }));
}

export async function getAnalytics(f: AnalyticsFilters): Promise<Analytics> {
  const rowFilters: unknown[][] = [];
  if (f.from) rowFilters.push(["attendance_date", ">=", f.from]);
  if (f.to) rowFilters.push(["attendance_date", "<=", f.to]);
  if (f.event) rowFilters.push(["event_code", "=", f.event]);

  const [everyone, rowsRes] = await Promise.all([
    list<P>("FOLK Users", ["mob_no", "full_name", "gender", "level", "pg_name", "profession", "event_code", "user_tag", "registered_by", "creation"], []),
    erp("GET", `/api/method/frappe.client.get_list?${qs({
      doctype: "FOLK Users Attendance", parent: "FOLK Users", fields: ["parent", "event_code", "attendance_date", "marked_by"], filters: rowFilters, limit_page_length: 0,
    })}`),
  ]);

  // Level and gender narrow both people and check-ins. Event narrows people to those registered for it
  // (check-ins are already limited to the event by rowFilters, so walk-ins still count).
  const demo = everyone.filter((p) => (!f.level || p.level === f.level) && (!f.gender || p.gender === f.gender));
  const demoSet = new Set(demo.map((p) => p.mob_no));
  const scope = demo.filter((p) => !f.event || p.event_code === f.event);
  const rows = (rowsRes.message as A[]).filter((r) => demoSet.has(r.parent));

  const attendedSet = new Set(rows.map((r) => r.parent));
  const attendedInScope = scope.filter((p) => attendedSet.has(p.mob_no)).length;
  const inRange = (p: P) => (!f.from || day(p.creation) >= f.from) && (!f.to || day(p.creation) <= f.to);

  const perPerson = group(rows, (r) => r.parent);
  const times = [...perPerson.values()].map((v) => v.length);
  const freq = (n: number) => times.filter((t) => (n === 4 ? t >= 4 : t === n)).length;
  const names = new Map(everyone.map((p) => [p.mob_no, p.full_name]));

  return {
    kpi: {
      people: scope.length,
      newRegistrations: scope.filter(inRange).length,
      attended: attendedSet.size,
      checkins: rows.length,
      rate: scope.length ? Math.round((100 * attendedInScope) / scope.length) : 0,
      notAttended: scope.length - attendedInScope,
    },
    byLevel: breakdown(scope, rows, (p) => p.level || NONE, LEVELS),
    byGender: breakdown(scope, rows, (p) => ({ M: "Male", F: "Female" })[p.gender ?? ""] ?? NONE, ["Male", "Female"]),
    byTag: breakdown(scope, rows, (p) => p.user_tag || "People", TAGS),
    byEvent: breakdown(scope, rows, (p) => p.event_code || NONE, []).sort((a, b) => b.checkins - a.checkins),
    frequency: [
      { label: "Came once", value: freq(1) }, { label: "Twice", value: freq(2) }, { label: "3 times", value: freq(3) }, { label: "4 or more", value: freq(4) },
    ],
    weekday: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label, i) => ({ label, value: rows.filter((r) => (weekdayOf(r.attendance_date) + 6) % 7 === i).length })),
    topAttendees: [...perPerson].map(([mob, v]) => ({ label: names.get(mob) ?? mob, hint: mob, value: v.length })).sort((a, b) => b.value - a.value).slice(0, 10),
    topPg: topText(scope, "pg_name"),
    topProfession: topText(scope, "profession"),
    byVolunteer: top(group(rows, (r) => r.marked_by || NONE)),
    byRegistrar: top(group(scope, (p) => p.registered_by || NONE)),
  };
}
