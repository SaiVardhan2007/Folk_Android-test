// Safe to import from both server and client code.
// A person's tag lives on their FOLK Users. Everyone starts as People; only an Admin can change it.
export const TAGS = ["People", "Coordinator", "Admin"] as const;
export type Tag = (typeof TAGS)[number];

export const asTag = (v: unknown): Tag => ((TAGS as readonly string[]).includes(v as string) ? (v as Tag) : "People");
