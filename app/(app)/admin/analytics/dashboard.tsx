import Link from "next/link";
import { X } from "lucide-react";
import type { Analytics, Event } from "@/lib/erpnext";
import { GENDERS, genderLabel } from "@/lib/genders";
import { LEVELS } from "@/lib/levels";
import { cn } from "@/lib/utils";
import { AutoForm } from "@/components/auto-form";
import { FilterDate, FilterPill } from "@/components/filter-field";
import { buttonVariants } from "@/components/ui/button";
import { BarList, BreakdownTable, Panel, StatTile } from "@/components/viz";

// Pure display. All filters and the "Show more" choices live in the URL, so every view is a shareable link.
const addDays = (s: string, n: number) => new Date(Date.parse(s + "T00:00:00Z") + n * 864e5).toISOString().slice(0, 10);

// Optional detail sections. Nothing here shows until it is picked, so the default view stays short.
export const SECTIONS = [
  { key: "level", label: "By level" }, { key: "gender", label: "By gender" }, { key: "tag", label: "By tag" }, { key: "event", label: "By event" },
  { key: "freq", label: "How often" }, { key: "weekday", label: "Weekdays" }, { key: "top", label: "Top attendees" }, { key: "marked", label: "Marked by" },
  { key: "pg", label: "PG / residence" }, { key: "job", label: "Profession" }, { key: "reg", label: "Registered by" },
] as const;
export type SectionKey = (typeof SECTIONS)[number]["key"];

export function Dashboard({ a, events, today, from, to, event, level, gender, show }: { a: Analytics; events: Event[]; today: string; from: string; to: string; event: string; level: string; gender: string; show: SectionKey[] }) {
  const shown = new Set<string>(show);
  const base = { from, to, event, level, gender };
  const href = (over: Partial<typeof base> & { show?: string[] }) => {
    const m = { ...base, ...over, show: (over.show ?? show).join(",") };
    return `/admin/analytics?${new URLSearchParams(Object.entries(m).filter(([, v]) => v) as [string, string][])}`;
  };
  const toggle = (k: SectionKey) => href({ show: shown.has(k) ? show.filter((s) => s !== k) : [...show, k] });
  const presets = [
    { label: "Today", f: today, t: today }, { label: "7 days", f: addDays(today, -6), t: today }, { label: "30 days", f: addDays(today, -29), t: today },
    { label: "This month", f: today.slice(0, 8) + "01", t: today }, { label: "All time", f: "", t: "" },
  ];
  const filtered = !!(from || to || event || level || gender);
  const summary = [from || to ? `${from || "start"} → ${to || "today"}` : "All time", event && events.find((e) => e.name === event)?.event_name, level, genderLabel(gender)].filter(Boolean).join(" · ");

  return (
    <div className="space-y-5">
      <AutoForm className="space-y-2">
        <input type="hidden" name="show" value={show.join(",")} />
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
          {presets.map((p) => (
            <Link key={p.label} href={href({ from: p.f, to: p.t })} className={cn(buttonVariants({ variant: p.f === from && p.t === to ? "default" : "outline", size: "sm" }), "h-9 shrink-0 rounded-full")}>{p.label}</Link>
          ))}
        </div>
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
          <FilterDate name="from" label="From date" value={from} max={today} />
          <FilterDate name="to" label="To date" value={to} max={today} />
          <FilterPill name="event" label="Event" value={event} options={events.map((e) => ({ value: e.name, label: e.event_name }))} />
          <FilterPill name="level" label="Level" value={level} options={LEVELS} />
          <FilterPill name="gender" label="Gender" value={gender} options={GENDERS} />
        </div>
      </AutoForm>

      <div className="flex items-center justify-between gap-3 text-sm text-muted-foreground">
        <span>{summary}</span>
        {filtered && <Link href={href({ from: "", to: "", event: "", level: "", gender: "" })} className="inline-flex shrink-0 items-center gap-1 hover:text-foreground"><X className="size-3.5" /> Clear</Link>}
      </div>

      <section aria-label="Headline numbers" className="grid grid-cols-2 gap-3 sm:grid-cols-4">
        <StatTile label="People" value={a.kpi.people} hint={event ? "registered for event" : undefined} />
        <StatTile label="Attended" value={a.kpi.attended} hint={`${a.kpi.rate}% of people`} />
        <StatTile label="Check-ins" value={a.kpi.checkins} hint="incl. repeat visits" />
        <StatTile label={from || to ? "New sign-ups" : "Not attended"} value={from || to ? a.kpi.newRegistrations : a.kpi.notAttended} hint={from || to ? "joined in period" : "no check-ins"} />
      </section>

      <div>
        <p className="mb-2 text-sm font-medium">Show more</p>
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
          {SECTIONS.map((s) => (
            <Link key={s.key} href={toggle(s.key)} aria-pressed={shown.has(s.key)}
              className={cn("h-9 shrink-0 rounded-full border px-3.5 text-sm leading-9 transition-colors", shown.has(s.key) ? "border-primary bg-primary text-primary-foreground" : "bg-background text-muted-foreground hover:text-foreground")}>
              {s.label}
            </Link>
          ))}
        </div>
      </div>

      {shown.has("level") && <Panel title="By level"><BreakdownTable rows={a.byLevel} firstColumn="Level" /></Panel>}
      {shown.has("gender") && <Panel title="By gender"><BreakdownTable rows={a.byGender} firstColumn="Gender" /></Panel>}
      {shown.has("tag") && <Panel title="By tag"><BreakdownTable rows={a.byTag} firstColumn="Tag" /></Panel>}
      {shown.has("event") && <Panel title="By event" description="People registered for each event, and how many showed up."><BreakdownTable rows={a.byEvent} firstColumn="Event" /></Panel>}
      {shown.has("freq") && <Panel title="How often people come" description="People by number of check-ins in this period."><BarList items={a.frequency} /></Panel>}
      {shown.has("weekday") && <Panel title="Check-ins by weekday"><BarList items={a.weekday} /></Panel>}
      {shown.has("top") && <Panel title="Most regular attendees" description="Top 10 by check-ins in this period."><BarList items={a.topAttendees} /></Panel>}
      {shown.has("marked") && <Panel title="Check-ins marked by" description="Which volunteers marked attendance."><BarList items={a.byVolunteer} /></Panel>}
      {shown.has("pg") && <Panel title="Top PG / residence"><BarList items={a.topPg} /></Panel>}
      {shown.has("job") && <Panel title="Top profession / college"><BarList items={a.topProfession} /></Panel>}
      {shown.has("reg") && <Panel title="Registered by" description="Who added people (self sign-up is its own row)."><BarList items={a.byRegistrar} /></Panel>}
    </div>
  );
}
