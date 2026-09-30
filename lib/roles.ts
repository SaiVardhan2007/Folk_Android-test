// Safe to import from both server and client code.
// A person's tag lives on their FOLK Users. Everyone starts as People; only an Admin can change it.
// The list of tags is read live from the user_tag field in ERPNext (see getTagOptions), so new tags added there
// show up in the app automatically. "Admin" is special: it is only ever granted or revoked in ERPNext.
export const DEFAULT_TAGS = ["People", "Coordinator", "Admin"];
export type Tag = string;

export const asTag = (v: unknown): Tag => (typeof v === "string" && v.trim() ? v : "People");

/** The main admin. Their tag can only be changed in ERPNext, never from the app. */
export const MAIN_ADMIN_MOB = "9133318576";
