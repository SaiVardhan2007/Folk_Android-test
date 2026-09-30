// Safe to import from both server and client code.
export const LEVELS = ["Folk Foundation", "Folk Prelims"] as const;
export type Level = (typeof LEVELS)[number];
