// Thin ERPNext REST client. The API key lives only in the Worker, never in the app.
import type { Bindings } from "./types";

export class ErpError extends Error {
  constructor(message: string, public status: number) {
    super(message);
  }
}

export const enc = encodeURIComponent;
export const qs = (o: Record<string, unknown>) =>
  Object.entries(o)
    .filter(([, v]) => v !== undefined)
    .map(([k, v]) => `${k}=${enc(typeof v === "string" ? v : JSON.stringify(v))}`)
    .join("&");
export const docPath = (doctype: string, name?: string) =>
  `/api/resource/${enc(doctype)}${name === undefined ? "" : `/${enc(name)}`}`;

export type Filters = unknown[][];

export class Erp {
  constructor(private env: Bindings) {}

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  async call(method: string, path: string, body?: unknown): Promise<any> {
    const res = await fetch(this.env.ERPNEXT_URL.replace(/\/$/, "") + path, {
      method,
      headers: {
        Authorization: `token ${this.env.ERPNEXT_API_KEY}:${this.env.ERPNEXT_API_SECRET}`,
        "Content-Type": "application/json",
        Accept: "application/json",
        // ERPNext sits behind Cloudflare, which blocks requests with no normal User-Agent (error 1010).
        "User-Agent": "folk-api/1.0",
      },
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (!res.ok) throw new ErpError((await res.text()).slice(0, 500), res.status);
    return res.json();
  }

  async list<T>(doctype: string, fields: string[], filters: Filters = [], extra: Record<string, unknown> = {}): Promise<T[]> {
    const r = await this.call("GET", `${docPath(doctype)}?${qs({ fields, filters, limit_page_length: 0, ...extra })}`);
    return r.data as T[];
  }

  async count(doctype: string, filters: Filters = [], extra: Record<string, unknown> = {}): Promise<number> {
    const r = await this.call("GET", `/api/method/frappe.client.get_count?${qs({ doctype, filters, ...extra })}`);
    return r.message as number;
  }

  async get<T>(doctype: string, name: string): Promise<T | null> {
    try {
      return (await this.call("GET", docPath(doctype, name))).data as T;
    } catch (e) {
      if (e instanceof ErpError && e.status === 404) return null;
      throw e;
    }
  }

  insert<T>(doctype: string, doc: Record<string, unknown>): Promise<{ data: T }> {
    return this.call("POST", docPath(doctype), doc);
  }
  update(doctype: string, name: string, patch: Record<string, unknown>) {
    return this.call("PUT", docPath(doctype, name), patch);
  }
  remove(doctype: string, name: string) {
    return this.call("DELETE", docPath(doctype, name));
  }
}
