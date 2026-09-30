import type { Metadata } from "next";
import { Download } from "lucide-react";
import { countAttendance, countRegistrations, currentEvent, listEvents } from "@/lib/erpnext";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { PageHeader } from "@/components/page-header";
import { cn } from "@/lib/utils";
import { ReportEventPicker } from "./picker";

export const metadata: Metadata = { title: "Reports" };
export const dynamic = "force-dynamic";

export default async function Reports({ searchParams }: { searchParams: Promise<{ event?: string }> }) {
  const [events, current, sp] = await Promise.all([listEvents(), currentEvent(), searchParams]);
  const event = sp.event || current || events[0]?.name;
  if (!event) return <Card><CardContent className="py-8 text-center text-muted-foreground">No events yet.</CardContent></Card>;
  const [registered, attended] = await Promise.all([countRegistrations(event), countAttendance(event)]);
  const q = encodeURIComponent(event);
  const btn = cn(buttonVariants({ variant: "outline", size: "lg" }), "h-10");

  return (
    <>
      <PageHeader title="Reports" description="Totals and exports for an event." />
      <div className="space-y-6">
        <ReportEventPicker events={events} value={event} />
        <div className="grid grid-cols-2 gap-4">
          <Card><CardHeader><CardDescription>Registered</CardDescription><CardTitle className="font-display text-4xl text-primary dark:text-gold">{registered}</CardTitle></CardHeader></Card>
          <Card><CardHeader><CardDescription>Attendance marked</CardDescription><CardTitle className="font-display text-4xl text-primary dark:text-gold">{attended}</CardTitle></CardHeader></Card>
        </div>
        <Card>
          <CardHeader><CardTitle className="text-base">Export</CardTitle><CardDescription>CSV files for the selected event.</CardDescription></CardHeader>
          <CardContent className="flex flex-col gap-2 sm:flex-row">
            <a className={btn} href={`/api/export/registrations?event=${q}`}><Download /> Registrations CSV</a>
            <a className={btn} href={`/api/export/attendance?event=${q}`}><Download /> Attendance CSV</a>
          </CardContent>
        </Card>
      </div>
    </>
  );
}
