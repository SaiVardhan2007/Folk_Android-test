"use client";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { Event } from "@/lib/erpnext";

/** Event dropdown. Used on Register, Attendance and Reports. */
export function EventSelect({ events, value, onChange }: { events: Event[]; value?: string; onChange?: (v: string) => void }) {
  const items = events.map((e) => ({ value: e.name, label: e.event_name }));
  return (
    <Select items={items} value={value} onValueChange={(v) => v && onChange?.(v)}>
      <SelectTrigger className="h-10 w-full"><SelectValue placeholder="Select event" /></SelectTrigger>
      <SelectContent>
        {items.map((i) => <SelectItem key={i.value} value={i.value}>{i.label}</SelectItem>)}
      </SelectContent>
    </Select>
  );
}
