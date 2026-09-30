// Low-level ERPNext REST helpers. Server-only: the API key never reaches the browser.
// Every other file in lib/erpnext/ is built on `erp`, `list`, `count` and `getDoc` from here.
import "server-only";

export class ErpError extends Error {
  constructor(message: string, public status: number) {
    super(message);
  }
}

export const enc = encodeURIComponent;
export const R = "/api/resource/";

/** URL path of one DocType, or of one document in it: docPath("FOLK Users", "9876543210"). */
export const docPath = (doctype: string, name?: string) => `${R}${enc(doctype)}${name === undefined ? "" : `/${enc(name)}`}`;

export const baseUrl = () => {
  const base = process.env.ERPNEXT_URL?.replace(/\/$/, "");
  if (!base) throw new ErpError("ERPNEXT_URL is not set", 500);
  return base;
};

/** Sends one authenticated request and returns the parsed JSON. Throws ErpError on any non-2xx response. */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function erp(method: string, path: string, body?: unknown): Promise<any> {
  const key = process.env.ERPNEXT_API_KEY;
  const secret = process.env.ERPNEXT_API_SECRET;
  if (!key || !secret) throw new ErpError("ERPNext API key is not configured", 500);

  const res = await fetch(`${baseUrl()}${path}`, {
    method,
    headers: { Authorization: `token ${key}:${secret}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
    cache: "no-store", // attendance data must always be live
  });
  if (!res.ok) throw new ErpError((await res.text()).slice(0, 500), res.status);
  return res.json();
}

/** Builds a query string; non-string values (arrays, objects) are JSON-encoded, as Frappe expects. */
export const qs = (o: Record<string, unknown>) =>
  Object.entries(o).map(([k, v]) => `${k}=${enc(typeof v === "string" ? v : JSON.stringify(v))}`).join("&");

export type Filters = unknown[][];

/** All documents of a DocType matching `filters` (limit_page_length: 0 = no paging). Pass `extra` for order_by, limit_start, or_filters... */
export async function list<T>(doctype: string, fields: string[], filters: Filters, extra: Record<string, unknown> = {}) {
  const r = await erp("GET", `${docPath(doctype)}?${qs({ fields, filters, limit_page_length: 0, ...extra })}`);
  return r.data as T[];
}

export async function count(doctype: string, filters: Filters) {
  const r = await erp("GET", `/api/method/frappe.client.get_count?${qs({ doctype, filters })}`);
  return r.message as number;
}

/** One document by name, or null if it doesn't exist (any other error is rethrown). */
export async function getDoc<T>(doctype: string, name: string): Promise<T | null> {
  try {
    return (await erp("GET", docPath(doctype, name))).data as T;
  } catch (e) {
    if (e instanceof ErpError && e.status === 404) return null;
    throw e;
  }
}
