// Admin analytics. Fetches only the few columns needed, computes in the Worker, and the route caches the result for 60 s.
import type { Erp, Filters } from "./erp";
import { LEVELS } from "./types";

type P = { name: string; mob_no: string; full_name: string; gender?: string; level?: string; pg_name?: string; profession?: string; event_code?: string; user_tag?: string; registered_by?: string; creation: string };
type A = { person: string; event_code: string; attendance_date: string; marked_by: string };
export type Filter = { from: string; to: string; event: string; level: string; gender: string };

const NONE = "(not set)";
const clean = (v?: string) => (v ?? "").trim();
const day = (s: string) => s.slice(0, 10);
const weekdayOf = (s: string) => new Date(s + "T00:00:00Z").getUTCDay();

function group<T>(items: T[], key: (t: T) => string) {
  const m = new Map<string, T[]>();
  for (const i of items) { const k = key(i); (m.get(k) ?? m.set(k, []).get(k)!).push(i); }
  return m;
}
const top = (m: Map<string, unknown[]>, n = 8) =>
  [...m].map(([label, v]) => ({ label, value: v.length })).sort((a, b) => b.value - a.value || a.label.localeCompare(b.label)).slice(0, n);

function breakdown(people: P[], rows: A[], key: (p: P) => string, order: readonly string[]) {
  const byMob = new Map(people.map((p) => [p.name, p]));
  const groups = group(people, key);
  const visits = new Map<string, { who: Set<string>; checkins: number }>();
  for (const r of rows) {
    const p = byMob.get(r.person);
    if (!p) continue;
    const k = key(p);
    const v = visits.get(k) ?? visits.set(k, { who: new Set(), checkins: 0 }).get(k)!;
    v.who.add(r.person);
    v.checkins++;
  }
  return [...new Set([...order, ...groups.keys()])]
    .map((k) => ({ key: k, people: groups.get(k)?.length ?? 0, attended: visits.get(k)?.who.size ?? 0, checkins: visits.get(k)?.checkins ?? 0 }))
    .filter((r) => r.people || r.checkins);
}

function topText(people: P[], field: "pg_name" | "profession") {
  const withValue = people.filter((p) => clean(p[field]));
  const groups = group(withValue, (p) => clean(p[field]).toLowerCase());
  return top(groups).map((c) => ({ ...c, label: clean(groups.get(c.label)![0][field]) }));
}

export async function analytics(erp: Erp, f: Filter, tags: string[]) {
  const rowFilters: Filters = [];
  if (f.from) rowFilters.push(["attendance_date", ">=", f.from]);
  if (f.to) rowFilters.push(["attendance_date", "<=", f.to]);
  if (f.event) rowFilters.push(["event_code", "=", f.event]);

  const [everyone, rowsAll] = await Promise.all([
    erp.list<P>("FOLK Users", ["name", "mob_no", "full_name", "gender", "level", "pg_name", "profession", "event_code", "user_tag", "registered_by", "creation"]),
    erp.list<A>("FOLK Attendance", ["person", "event_code", "attendance_date", "marked_by"], rowFilters),
  ]);

  const demo = everyone.filter((p) => (!f.level || p.level === f.level) && (!f.gender || p.gender === f.gender));
  const demoSet = new Set(demo.map((p) => p.name));
  const scope = demo.filter((p) => !f.event || p.event_code === f.event);
  const rows = rowsAll.filter((r) => demoSet.has(r.person));

  const attendedSet = new Set(rows.map((r) => r.person));
  const attendedInScope = scope.filter((p) => attendedSet.has(p.name)).length;
  const inRange = (p: P) => (!f.from || day(p.creation) >= f.from) && (!f.to || day(p.creation) <= f.to);
  const perPerson = group(rows, (r) => r.person);
  const times = [...perPerson.values()].map((v) => v.length);
  const freq = (n: number) => times.filter((t) => (n === 4 ? t >= 4 : t === n)).length;
  const mobOf = new Map(everyone.map((p) => [p.name, p.mob_no]));
  const names = new Map(everyone.map((p) => [p.name, p.full_name]));

  return {
    kpi: {
      people: scope.length, newRegistrations: scope.filter(inRange).length, attended: attendedSet.size, checkins: rows.length,
      rate: scope.length ? Math.round((100 * attendedInScope) / scope.length) : 0, notAttended: scope.length - attendedInScope,
    },
    byLevel: breakdown(scope, rows, (p) => p.level || NONE, LEVELS),
    byGender: breakdown(scope, rows, (p) => ({ M: "Male", F: "Female" } as Record<string, string>)[p.gender ?? ""] ?? NONE, ["Male", "Female"]),
    byTag: breakdown(scope, rows, (p) => p.user_tag || "Public", tags),
    byEvent: breakdown(scope, rows, (p) => p.event_code || NONE, []).sort((a, b) => b.checkins - a.checkins),
    frequency: [
      { label: "Came once", value: freq(1) }, { label: "Twice", value: freq(2) }, { label: "3 times", value: freq(3) }, { label: "4 or more", value: freq(4) },
    ],
    weekday: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((label, i) => ({ label, value: rows.filter((r) => (weekdayOf(r.attendance_date) + 6) % 7 === i).length })),
    topAttendees: [...perPerson].map(([mob, v]) => ({ label: names.get(mob) ?? mob, hint: mobOf.get(mob) ?? "", value: v.length })).sort((a, b) => b.value - a.value).slice(0, 10),
    topPg: topText(scope, "pg_name"),
    topProfession: topText(scope, "profession"),
    byVolunteer: top(group(rows, (r) => (r.marked_by ? names.get(r.marked_by) ?? r.marked_by : NONE))),
    byRegistrar: top(group(scope, (p) => p.registered_by || NONE)),
  };
}
