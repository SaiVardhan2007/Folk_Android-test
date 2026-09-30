// Events ("FOLK Event") and the single "current event" setting ("FOLK Settings") that pages default to.
import { docPath, erp, list } from "./client";

export type Event = { name: string; event_name: string };

const SETTINGS = docPath("FOLK Settings", "FOLK Settings"); // a Single DocType: name = doctype

export const listEvents = () => list<Event>("FOLK Event", ["name", "event_name"], [], { order_by: "creation desc" });

/** The admin-chosen current event, or null if none is set (or settings can't be read). */
export async function currentEvent() {
  const r = await erp("GET", SETTINGS).catch(() => null);
  return (r?.data?.current_event as string | undefined) || null;
}

export const setCurrentEvent = (event: string) => erp("PUT", SETTINGS, { current_event: event });

/** Which event a page should use: the one asked for in the URL (if it exists), else the current event, else the newest. */
export const pickEvent = (events: Event[], requested: string | undefined, current: string | null) =>
  events.find((e) => e.name === requested)?.name ?? current ?? events[0]?.name;
