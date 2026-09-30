"use client";
import { useRouter } from "next/navigation";
import type { Event } from "@/lib/erpnext";
import { EventSelect } from "@/components/event-select";

export function ReportEventPicker({ events, value }: { events: Event[]; value: string }) {
  const router = useRouter();
  return <EventSelect events={events} value={value} onChange={(v) => router.replace(`/reports?event=${encodeURIComponent(v)}`)} />;
}
