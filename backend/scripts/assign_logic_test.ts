// Run: npx tsc --noEmit false --outDir <dir> ... then node (see docs). Checks the Min/Max rule with the examples from docs/ASSIGN_WIZARD.md.
import { shareOut, passes, type Member } from "../src/calls";
const eq = (a: unknown, b: unknown, m: string) => { if (JSON.stringify(a) !== JSON.stringify(b)) { console.error("FAIL", m, a, b); process.exit(1); } };
const mk = (n: number, min: number, max: number, lastMax = max): Member[] => Array.from({ length: n }, (_, i) => ({ id: `c${i}`, name: `c${i}`, min, max: i === n - 1 ? lastMax : max }));
const counts = (r: { given: { coordinator: string }[] }, n: number) => Array.from({ length: n }, (_, i) => r.given.filter((g) => g.coordinator === `c${i}`).length);
const items = (n: number) => Array.from({ length: n }, (_, i) => i);

let r = shareOut(items(100), mk(10, 3, 10), new Map());
eq(counts(r, 10), Array(10).fill(10), "100 over 10 (min3,max10)");
r = shareOut(items(130), mk(10, 3, 10, Infinity), new Map());
eq(counts(r, 10), [...Array(9).fill(10), 40], "130, last has no max"); eq(r.left.length, 0, "no leftover");
r = shareOut(items(130), mk(10, 3, 10), new Map());
eq(r.left.length, 30, "30 left over");
r = shareOut(items(8), mk(3, 5, 10), new Map());
eq(counts(r, 3).reduce((a, b) => a + b), 8, "short of minimums still shares all"); eq(Math.max(...counts(r, 3)) - Math.min(...counts(r, 3)) <= 1, true, "evenly");
r = shareOut(items(12), [{ id: "a", name: "a", min: 6, max: 6 }, { id: "b", name: "b", min: 0, max: 100 }], new Map());
eq(counts({ given: r.given.map((g) => ({ coordinator: g.coordinator === "a" ? "c0" : "c1" })) }, 2), [6, 6], "min fills before even share");
r = shareOut([1, 2, 3, 4], mk(2, 0, 10), new Map(), (i) => (i <= 3 ? "c0" : undefined));
eq(r.kept, 3, "kept with previous");
const a = { college: ["x"], skill: [] as string[] };
eq(passes(a, [{ field: "college", mode: "except", values: ["x"] }]), false, "except");
eq(passes(a, [{ field: "skill", mode: "only", values: [""] }]), true, "empty matches");
eq(passes(a, [{ field: "college", mode: "only", values: ["y"] }], "college"), true, "skip own field");
console.log("ok");
