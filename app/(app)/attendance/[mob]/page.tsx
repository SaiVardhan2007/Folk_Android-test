import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { currentEvent, getRegistration, hasMarked, listEvents, pickEvent } from "@/lib/erpnext";
import { PageHeader } from "@/components/page-header";
import { normalizeMobile, todayIST } from "@/lib/utils";
import { MarkForm } from "./mark-form";

export const metadata: Metadata = { title: "Mark attendance" };
export const dynamic = "force-dynamic";

// Step 2: show the person (or a blank form if not registered yet) and mark them present.
export default async function MarkPage({ params, searchParams }: { params: Promise<{ mob: string }>; searchParams: Promise<{ event?: string }> }) {
  const [{ mob: raw }, sp] = await Promise.all([params, searchParams]);
  const mob = normalizeMobile(raw);
  if (!mob) notFound();

  const [events, current] = await Promise.all([listEvents(), currentEvent()]);
  const event = pickEvent(events, sp.event, current);
  if (!event) notFound();

  const reg = await getRegistration(mob);
  const marked = reg ? hasMarked(reg, event, todayIST()) : false;
  const eventName = events.find((e) => e.name === event)?.event_name ?? event;
  const back = `/attendance?event=${encodeURIComponent(event)}`;

  return (
    <>
      <PageHeader backHref={back} title={reg ? reg.full_name : "New attendee"} description={`${mob} · ${eventName}`} />
      <MarkForm mob={mob} event={event} reg={reg} markedToday={marked} backHref={back} />
    </>
  );
}
