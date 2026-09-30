import type { Metadata } from "next";
import { currentEvent, listEvents, pickEvent } from "@/lib/erpnext";
import { Card, CardContent } from "@/components/ui/card";
import { PageHeader } from "@/components/page-header";
import Attendance from "./attendance";

export const metadata: Metadata = { title: "Attendance" };
export const dynamic = "force-dynamic";

// Step 1 of marking attendance: pick the event, type a mobile number (see attendance.tsx).
// Step 2 is /attendance/[mob].
export default async function AttendancePage({ searchParams }: { searchParams: Promise<{ event?: string }> }) {
  const [events, current, sp] = await Promise.all([listEvents(), currentEvent(), searchParams]);
  const event = pickEvent(events, sp.event, current);
  return (
    <>
      <PageHeader title="Mark attendance" description="Type the 10-digit mobile number. The search runs automatically." />
      {!event
        ? <Card><CardContent className="py-8 text-center text-muted-foreground">No events yet. Ask an admin to create one in ERPNext (FOLK Event).</CardContent></Card>
        : <Attendance events={events} event={event} />}
    </>
  );
}
