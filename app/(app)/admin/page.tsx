import type { Metadata } from "next";
import Link from "next/link";
import { ChevronLeft, ChevronRight, Download, X } from "lucide-react";
import { requireAdmin } from "@/lib/auth";
import { currentEvent, getTagOptions, listEvents, queryPeople } from "@/lib/erpnext";
import { PAGE_SIZE, parsePeopleQuery, SORTS, toParams, type SearchParams } from "@/lib/admin-query";
import { GENDERS } from "@/lib/genders";
import { LEVELS } from "@/lib/levels";
import { AutoForm } from "@/components/auto-form";
import { FilterDate, FilterInput, FilterPill } from "@/components/filter-field";
import { buttonVariants } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { cn } from "@/lib/utils";
import { CurrentEventPicker } from "./current-event-picker";
import { PeopleList } from "./people-list";

export const metadata: Metadata = { title: "Admin" };
export const dynamic = "force-dynamic";

export default async function AdminPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const [me, sp, events, current, tags] = await Promise.all([requireAdmin(), searchParams, listEvents(), currentEvent(), getTagOptions()]);
  const q = parsePeopleQuery(sp);
  const { people, total } = await queryPeople(q);
  const pages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const page = Math.min(q.page, pages);
  const link = (p: number) => `/admin?${toParams(q, { page: p })}`;
  const active = ["q", "tag", "level", "gender", "event", "pw", "att", "from", "to"].filter((k) => q[k as keyof typeof q]).length;
  const pageBtn = (off: boolean) => cn(buttonVariants({ variant: "outline" }), "h-10 gap-1", off && "pointer-events-none opacity-50");

  return (
    <>
      {/* Search on top; one scrollable row of dropdown pills below. Dropdowns and dates apply immediately. */}
      <AutoForm className="mb-4 space-y-2">
        <div className="flex gap-2">
          <FilterInput name="q" data-manual defaultValue={q.q} placeholder="Search name or mobile" aria-label="Search" className="rounded-full" />
          <a href={`/api/export/people?${toParams(q, { page: 1 })}`} aria-label="Export CSV" title="Export CSV" className={cn(buttonVariants({ variant: "outline" }), "size-10 shrink-0 rounded-full p-0")}><Download className="size-4" /></a>
          <CurrentEventPicker events={events} current={current} />
        </div>
        <div className="-mx-4 flex gap-2 overflow-x-auto px-4 pb-1 sm:mx-0 sm:flex-wrap sm:px-0">
          <FilterPill name="tag" label="Tag" value={q.tag} options={tags} />
          <FilterPill name="level" label="Level" value={q.level} options={LEVELS} />
          <FilterPill name="gender" label="Gender" value={q.gender} options={GENDERS} />
          <FilterPill name="event" label="Event" value={q.event} options={events.map((e) => ({ value: e.name, label: e.event_name }))} />
          <FilterPill name="pw" label="Password" value={q.pw} options={[{ value: "set", label: "Has password" }, { value: "unset", label: "No password" }]} />
          <FilterPill name="att" label="Attendance" value={q.att} options={[{ value: "yes", label: "Attended" }, { value: "no", label: "Never attended" }]} />
          <FilterDate name="from" label="Joined from" value={q.from} />
          <FilterDate name="to" label="Joined to" value={q.to} />
          <select name="sort" defaultValue={q.sort} aria-label="Sort by" className="h-9 shrink-0 rounded-full border bg-background px-3 text-sm text-muted-foreground outline-none focus-visible:ring-3 focus-visible:ring-ring/40 sm:ml-auto">
            {Object.entries(SORTS).map(([value, s]) => <option key={value} value={value}>{s.label}</option>)}
          </select>
        </div>
      </AutoForm>

      <div className="mb-3 flex items-center justify-between gap-3 text-sm text-muted-foreground" aria-live="polite">
        <span>{total} {total === 1 ? "person" : "people"}{active > 0 && " match"}</span>
        {active > 0 && <Link href="/admin" className="inline-flex items-center gap-1 hover:text-foreground"><X className="size-3.5" /> Clear filters</Link>}
      </div>
      {people.length === 0
        ? <Card><CardContent className="py-8 text-center text-muted-foreground">No one matches these filters.</CardContent></Card>
        : <PeopleList people={people} myMob={me.mob} tags={tags} />}

      {pages > 1 && (
        <nav aria-label="Pages" className="mt-4 flex items-center justify-between gap-3">
          <Link href={link(page - 1)} aria-disabled={page <= 1} tabIndex={page <= 1 ? -1 : undefined} className={pageBtn(page <= 1)}><ChevronLeft className="size-4" /> Previous</Link>
          <span className="text-sm text-muted-foreground">Page {page} of {pages}</span>
          <Link href={link(page + 1)} aria-disabled={page >= pages} tabIndex={page >= pages ? -1 : undefined} className={pageBtn(page >= pages)}>Next <ChevronRight className="size-4" /></Link>
        </nav>
      )}
    </>
  );
}
