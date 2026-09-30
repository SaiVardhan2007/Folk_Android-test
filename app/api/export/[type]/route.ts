// CSV downloads: /api/export/people (Admin, filtered like the Admin page), /registrations?event=... and /attendance?event=...
// Route handlers are not covered by the (app) layout's sign-in check, so each one checks the session itself.
import { getSession } from "@/lib/auth";
import { list } from "@/lib/erpnext";
import { parsePeopleQuery, peopleFilters, searchFilters, SORTS } from "@/lib/admin-query";
import { ATTENDANCE_CSV_COLS, REGISTRATION_CSV_COLS, allAttendance, allRegistrations } from "@/lib/erpnext";
import { toCsv } from "@/lib/utils";

const PEOPLE_COLS = ["mob_no", "full_name", "gender", "level", "pg_name", "profession", "event_code", "user_tag", "attendance_count", "last_attended_on", "registered_by", "creation"];

const csvResponse = (csv: string, filename: string) =>
  new Response(csv, { headers: { "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="${filename}"` } });

export async function GET(req: Request, { params }: { params: Promise<{ type: string }> }) {
  const session = await getSession();
  if (!session) return new Response("Unauthorized", { status: 401 });
  const { type } = await params;
  const url = new URL(req.url);

  if (type === "people") {
    // Admin-only; same filters as the Admin People page. Never includes the password hash.
    if (session.tag !== "Admin") return new Response("Forbidden", { status: 403 });
    const q = parsePeopleQuery(Object.fromEntries(url.searchParams));
    const or_filters = searchFilters(q.q);
    const rows = await list<Record<string, unknown>>("FOLK Users", PEOPLE_COLS, peopleFilters(q), { order_by: SORTS[q.sort].order, ...(or_filters && { or_filters }) });
    return csvResponse(toCsv(rows, PEOPLE_COLS), "people.csv");
  }

  if (type !== "registrations" && type !== "attendance") return new Response("Not found", { status: 404 });
  const event = url.searchParams.get("event");
  if (!event) return new Response("event is required", { status: 400 });
  const csv = type === "registrations" ? toCsv(await allRegistrations(event), REGISTRATION_CSV_COLS) : toCsv(await allAttendance(event), ATTENDANCE_CSV_COLS);
  return csvResponse(csv, `${type}-${event}.csv`);
}
