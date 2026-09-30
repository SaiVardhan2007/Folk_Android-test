import type { Metadata } from "next";
import { getAnalytics, listEvents } from "@/lib/erpnext";
import { GENDERS } from "@/lib/genders";
import { one, validDate, type SearchParams } from "@/lib/admin-query";
import { LEVELS } from "@/lib/levels";
import { todayIST } from "@/lib/utils";
import { Dashboard, SECTIONS, type SectionKey } from "./dashboard";

export const metadata: Metadata = { title: "Analytics" };
export const dynamic = "force-dynamic";

// Reads + validates the URL filters, fetches the numbers, hands everything to <Dashboard>.
export default async function AnalyticsPage({ searchParams }: { searchParams: Promise<SearchParams> }) {
  const sp = await searchParams;
  const today = todayIST();
  let from = validDate(one(sp.from)), to = validDate(one(sp.to));
  if (from && to && from > to) [from, to] = [to, from];
  const event = one(sp.event), gender = GENDERS.some((g) => g.value === one(sp.gender)) ? one(sp.gender) : "";
  const level = (LEVELS as readonly string[]).includes(one(sp.level)) ? one(sp.level) : "";

  const keys = SECTIONS.map((x) => x.key) as readonly string[];
  const show = one(sp.show).split(",").filter((k, i, all) => keys.includes(k) && all.indexOf(k) === i) as SectionKey[];

  const [events, a] = await Promise.all([listEvents(), getAnalytics({ from, to, event, level, gender })]);
  return <Dashboard a={a} events={events} today={today} from={from} to={to} event={event} level={level} gender={gender} show={show} />;
}
