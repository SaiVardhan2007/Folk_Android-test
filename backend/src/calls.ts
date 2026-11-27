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

/** Fisher-Yates. The random source can be replaced (tests). */
export function shuffle<T>(a: readonly T[], rnd: () => number = Math.random): T[] {
  const out = [...a];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [out[i], out[j]] = [out[j]!, out[i]!];
  }
  return out;
}

// ---------- assignment wizard: filters and Min/Max sharing

/** One filter: keep contacts whose value is in `values` ("only"), or drop those whose value is in `values` ("except"). "" means "empty". */
export type PoolFilter = { field: string; mode: "only" | "except"; values: string[] };

/** A contact's values per field. Single-value fields have one entry ("" when empty); skills and interests may have several. */
export type Attrs = Record<string, string[]>;

/** Does the contact pass every filter? A filter on `skip` is ignored (used to count the values of the field being looked at). */
export function passes(attrs: Attrs, filters: readonly PoolFilter[], skip = ""): boolean {
  for (const f of filters) {
    if (f.field === skip || !f.values.length) continue;
    const mine = attrs[f.field]?.length ? attrs[f.field]! : [""];
    const hit = mine.some((v) => f.values.includes(v));
    if (f.mode === "only" ? !hit : hit) return false;
  }
  return true;
}

export type Member = { id: string; name: string; min: number; max: number };

/**
 * Shares items among coordinators using a Minimum and a Maximum (Infinity = no maximum). Counts only what is given in this
 * assignment (`given` carries what each coordinator already got from earlier groups of the same plan).
 *  1. an item that should stay with the coordinator who had it goes there first, while they are under their Max;
 *  2. everyone is brought up to their Min, one item at a time to whoever has the fewest;
 *  3. the rest go one at a time to whoever has the fewest and is under their Max.
 * Items nobody has room for come back in `left`. Never mutates the input except `given`.
 */
export function shareOut<T>(
  items: readonly T[], members: readonly Member[], given: Map<string, number>, prefer?: (item: T) => string | undefined,
): { given: { item: T; coordinator: string }[]; left: T[]; kept: number } {
  const out: { item: T; coordinator: string }[] = [];
  const ms = members.map((m) => ({ ...m, min: Math.min(m.min, m.max) }));
  const n = (id: string) => given.get(id) ?? 0;
  const room = (m: Member) => n(m.id) < m.max;
  const give = (item: T, id: string) => { given.set(id, n(id) + 1); out.push({ item, coordinator: id }); };
  const fewest = (list: Member[]) => list.reduce<Member | null>((b, m) => (b === null || n(m.id) < n(b.id) ? m : b), null);

  const rest: T[] = [];
  for (const item of items) {
    const want = prefer?.(item);
    const m = want === undefined ? undefined : ms.find((x) => x.id === want);
    if (m && room(m)) give(item, m.id);
    else rest.push(item);
  }
  const kept = out.length;
  const left: T[] = [];
  for (const item of rest) {
    const needy = ms.filter((m) => room(m) && n(m.id) < m.min);
    const pick = fewest(needy.length ? needy : ms.filter(room));
    if (pick) give(item, pick.id);
    else left.push(item);
  }
  return { given: out, left, kept };
}
