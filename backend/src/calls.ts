// Rules for the calling system. One place, so the app, the stats and the API can never disagree.

export const STATUSES = [
  "Not Done", "Joining the session", "Next Week will join", "Out of Station", "Wrong Number",
  "Shifted to Home Town", "Need to Call Again", "Available on Weekend", "Others",
] as const;
export type CallStatus = (typeof STATUSES)[number];

export const PENDING = "Not Done";
/** Outcomes counted as positive everywhere (caller stats, admin analytics). */
export const POSITIVE: readonly string[] = ["Joining the session", "Next Week will join"];
/** Outcomes an admin can hand to another coordinator for a second attempt. */
export const FOLLOW_UP: readonly string[] = ["Need to Call Again", "Available on Weekend"];
/** The caller must write a note for these. */
export const NOTE_REQUIRED: readonly string[] = ["Others"];

export type Coord = { id: string; name: string; load: number; cap: number };

/**
 * Hands each item to the coordinator who currently has the fewest contacts and still has room.
 * Items nobody has room for are returned in `left`. Never mutates the input.
 */
export function distribute<T>(items: T[], coords: Coord[]): { given: { item: T; coordinator: string }[]; left: T[]; added: Map<string, number> } {
  const load = new Map(coords.map((c) => [c.id, c.load]));
  const cap = new Map(coords.map((c) => [c.id, c.cap]));
  const added = new Map<string, number>();
  const given: { item: T; coordinator: string }[] = [];
  const left: T[] = [];
  for (const item of items) {
    let best: string | null = null;
    for (const c of coords) {
      if ((load.get(c.id) ?? 0) >= (cap.get(c.id) ?? Infinity)) continue;
      if (best === null || (load.get(c.id) ?? 0) < (load.get(best) ?? 0)) best = c.id;
    }
    if (best === null) { left.push(item); continue; }
    load.set(best, (load.get(best) ?? 0) + 1);
    added.set(best, (added.get(best) ?? 0) + 1);
    given.push({ item, coordinator: best });
  }
  return { given, left, added };
}
