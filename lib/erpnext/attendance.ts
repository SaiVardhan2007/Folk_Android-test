// Attendance lives inside each person's FOLK Users record, as rows of the child table "FOLK Users Attendance".
// Every write reads the person, changes the rows, and saves with the `modified` stamp, so two volunteers
// saving the same person at once can't overwrite each other (ERPNext rejects the stale save and we retry).
import { ErpError, docPath, erp, list, qs } from "./client";
import { getRegistration, type Registration } from "./registrations";

const PARENT = "FOLK Users";
const CHILD = "FOLK Users Attendance";
const MAX_RETRIES = 2;

export type AttendanceEntry = { name: string; event_code: string; attendance_date: string; ts: string; marked_by: string };
export type AttendanceRow = AttendanceEntry & { mob_no: string; attendee_name: string };

/** Has this person already been marked for this event on this date? */
export const hasMarked = (u: Pick<Registration, "attendance">, event: string, date: string) =>
  !!u.attendance?.some((a) => a.event_code === event && a.attendance_date === date);

const isConflict = (e: unknown) => e instanceof ErpError && (e.status === 409 || /TimestampMismatch|has been modified/i.test(e.message));

/** Reads the person, lets `change` edit their attendance rows (return null = nothing to do), saves. Retries if someone else saved first. */
async function saveRows(mob: string, change: (rows: AttendanceEntry[]) => AttendanceEntry[] | null) {
  for (let attempt = 0; ; attempt++) {
    const doc = await getRegistration(mob);
    if (!doc) throw new ErpError("Person not found", 404);
    const rows = change(doc.attendance ?? []);
    if (!rows) return "unchanged" as const;
    const last = rows.map((r) => r.attendance_date).sort().pop() ?? "";
    try {
      // `count` and `last_attended_on` are denormalised onto the person so the Admin list can sort/filter by them.
      await erp("PUT", docPath(PARENT, mob), { modified: doc.modified, attendance: rows, attendance_count: rows.length, last_attended_on: last || null });
      return "saved" as const;
    } catch (e) {
      if (!(isConflict(e) && attempt < MAX_RETRIES)) throw e;
    }
  }
}

/** Adds one check-in unless that person is already marked for this event today. */
export const markAttendance = async (mob: string, row: { event_code: string; attendance_date: string; ts: string; marked_by: string }) =>
  (await saveRows(mob, (rows) => (hasMarked({ attendance: rows }, row.event_code, row.attendance_date) ? null : [...rows, { name: "", ...row }])))
    === "saved" ? ("marked" as const) : ("already" as const);

/** Removes one check-in row (by its row name) from a person. */
export const undoAttendance = (mob: string, rowName: string) =>
  saveRows(mob, (rows) => (rows.some((r) => r.name === rowName) ? rows.filter((r) => r.name !== rowName) : null));

// ---- reads across everyone (child-table rows, optionally joined with names from FOLK Users)
type ChildRow = AttendanceEntry & { parent: string };

function childRows(filters: unknown[][]) {
  return erp("GET", `/api/method/frappe.client.get_list?${qs({
    doctype: CHILD, parent: PARENT, fields: ["name", "parent", "event_code", "attendance_date", "ts", "marked_by"], filters, limit_page_length: 0,
  })}`).then((r) => r.message as ChildRow[]);
}

async function rowsWhere(filters: unknown[][]) {
  const rows = await childRows(filters);
  const parents = [...new Set(rows.map((x) => x.parent))];
  const people = parents.length ? await list<{ name: string; full_name: string }>(PARENT, ["name", "full_name"], [["name", "in", parents]]) : [];
  const names = new Map(people.map((p) => [p.name, p.full_name]));
  return rows.map<AttendanceRow>((x) => ({ ...x, mob_no: x.parent, attendee_name: names.get(x.parent) ?? x.parent }));
}
const newestFirst = (a: AttendanceRow, b: AttendanceRow) => b.ts.localeCompare(a.ts);

/** Check-ins for one event on one date, newest first (the live list on the Attendance screen). */
export const todaysAttendance = async (event: string, date: string) =>
  (await rowsWhere([["event_code", "=", event], ["attendance_date", "=", date]])).sort(newestFirst);

/** Total check-ins for an event. Skips the name lookup: only the number is needed. */
export const countAttendance = async (event: string) => (await childRows([["event_code", "=", event]])).length;

// ---- CSV export (Reports page)
export const ATTENDANCE_CSV_COLS = ["ts", "mob_no", "attendee_name", "event_code", "marked_by"];
export const allAttendance = async (event: string) => (await rowsWhere([["event_code", "=", event]])).sort((a, b) => a.ts.localeCompare(b.ts));
