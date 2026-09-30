import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { requireSession } from "@/lib/auth";
import { countAttendance, countRegistrations, currentEvent, listEvents } from "@/lib/erpnext";
import { navFor } from "@/lib/nav";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { PageHeader } from "@/components/page-header";

export const dynamic = "force-dynamic";

/** Headline numbers for the current event; returns a `hint` message instead if they can't be shown. */
async function stats() {
  try {
    const event = await currentEvent();
    if (!event) return { hint: "No current event is set. Set one in ERPNext > FOLK Settings." };
    const [registered, attended, events] = await Promise.all([countRegistrations(event), countAttendance(event), listEvents()]);
    // show the event's name, not its code
    return { event: events.find((e) => e.name === event)?.event_name ?? event, registered, attended };
  } catch {
    return { hint: "Couldn't load numbers from ERPNext." };
  }
}

export default async function HomePage() {
  const [session, s] = await Promise.all([requireSession(), stats()]);
  return (
    <>
      <PageHeader title={`Hare Krishna, ${session.name.split(" ")[0]}`} description="What would you like to do?" />
      {"hint" in s ? (
        <p className="mb-6 text-sm text-muted-foreground">{s.hint}</p>
      ) : (
        <div className="mb-6 grid grid-cols-2 gap-4">
          <Card><CardHeader><CardDescription>Registered · {s.event}</CardDescription><CardTitle className="font-display text-4xl text-primary dark:text-gold">{s.registered}</CardTitle></CardHeader></Card>
          <Card><CardHeader><CardDescription>Attendance marked</CardDescription><CardTitle className="font-display text-4xl text-primary dark:text-gold">{s.attended}</CardTitle></CardHeader></Card>
        </div>
      )}
      <div className="grid gap-4 sm:grid-cols-2">
        {navFor(session.tag).filter((n) => n.description).map(({ href, label, description, icon: Icon }) => (
          <Link key={href} href={href}>
            <Card className="h-full transition-all hover:-translate-y-0.5 hover:ring-gold/60">
              <CardContent className="flex items-center gap-4">
                <span className="grid size-10 place-items-center rounded-full bg-accent text-primary"><Icon className="size-5" /></span>
                <div className="flex-1"><p className="font-medium">{label}</p><p className="text-sm text-muted-foreground">{description}</p></div>
                <ArrowRight className="size-4 text-muted-foreground" />
              </CardContent>
            </Card>
          </Link>
        ))}
      </div>
    </>
  );
}
