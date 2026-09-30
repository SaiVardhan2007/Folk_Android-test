"use client";
import { useTransition } from "react";
import { CalendarCheck } from "lucide-react";
import { toast } from "sonner";
import type { Event } from "@/lib/erpnext/events";
import { setCurrentEventAction } from "./actions";

// Small pill in the People toolbar: pick the default event for Register / Attendance / Home.
export function CurrentEventPicker({ events, current }: { events: Event[]; current: string | null }) {
  const [pending, start] = useTransition();
  const change = (event: string) =>
    start(async () => { const r = await setCurrentEventAction(event); if (r.ok) toast.success(r.message); else toast.error(r.message); });

  return (
    <label title="Current event (default on Register and Attendance)" className="relative inline-flex h-10 shrink-0 items-center">
      <CalendarCheck className="pointer-events-none absolute left-3 size-4 text-muted-foreground" />
      <select value={current ?? ""} disabled={pending} aria-label="Current event" onChange={(e) => change(e.target.value)}
        className="h-10 w-36 truncate rounded-full border bg-background pl-9 pr-3 text-sm outline-none focus-visible:ring-3 focus-visible:ring-ring/40 disabled:opacity-60 sm:w-48">
        {!current && <option value="" disabled>Current event</option>}
        {events.map((e) => <option key={e.name} value={e.name}>{e.event_name}</option>)}
      </select>
    </label>
  );
}
