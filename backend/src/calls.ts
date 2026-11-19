// Rules for the calling system. One place, so the app, the stats and the API can never disagree.

export const STATUSES = [
  "Not Done", "Joining the session", "Next Week will join", "Out of Station", "Wrong Number",
  "Shifted to Home Town", "Need to Call Again", "Available on Weekend", "Not Answered", "Not Coming", "Not Interested", "Others",
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

/** Fisher-Yates. The random source can be replaced (tests). */
export function shuffle<T>(a: readonly T[], rnd: () => number = Math.random): T[] {
  const out = [...a];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

/**
 * Picks `n` items from groups (for example one group per coordinator), always taking from the group that still has the most,
 * so a "give me 100 from the others" request empties the busiest coordinators first and never favours one.
 */
export function takeFairly<T>(groups: Map<string, T[]>, n: number): T[] {
  const left = new Map([...groups].map(([k, v]) => [k, [...v]]));
  const out: T[] = [];
  while (out.length < n) {
    let big: T[] | null = null;
    for (const v of left.values()) if (v.length && (big === null || v.length > big.length)) big = v;
    if (!big) break;
    out.push(big.pop()!);
  }
  return out;
}

/**
 * Hands each item to a coordinator who still has room.
 * - `prefer(item)` names the coordinator an item should stay with (the one who had it before). It is honoured first, as long as that
 *   coordinator is in `coords` and under their limit.
 * - Everything else goes to whoever currently has the fewest contacts (so the shares come out equal).
 * Items nobody has room for are returned in `left`. Never mutates the input.
 */
export function distribute<T>(
  items: T[], coords: Coord[], prefer?: (item: T) => string | undefined,
): { given: { item: T; coordinator: string }[]; left: T[]; added: Map<string, number>; kept: number } {
  const load = new Map(coords.map((c) => [c.id, c.load]));
  const cap = new Map(coords.map((c) => [c.id, c.cap]));
  const added = new Map<string, number>();
  const given: { item: T; coordinator: string }[] = [];
  const rest: T[] = [];
  const room = (id: string) => (load.get(id) ?? 0) < (cap.get(id) ?? Infinity);
  const give = (item: T, id: string) => {
    load.set(id, (load.get(id) ?? 0) + 1);
    added.set(id, (added.get(id) ?? 0) + 1);
    given.push({ item, coordinator: id });
  };
  for (const item of items) {
    const want = prefer?.(item);
    if (want !== undefined && load.has(want) && room(want)) give(item, want);
    else rest.push(item);
  }
  const kept = given.length;
  const left: T[] = [];
  for (const item of rest) {
    let best: string | null = null;
    for (const c of coords) {
      if (!room(c.id)) continue;
      if (best === null || (load.get(c.id) ?? 0) < (load.get(best) ?? 0)) best = c.id;
    }
    if (best === null) left.push(item);
    else give(item, best);
  }
  return { given, left, added, kept };
}
