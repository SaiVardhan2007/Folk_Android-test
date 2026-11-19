// The shared print queue. ONE instance ("main") receives a receipt from any phone and hands it, one at a time, to a phone that is
// connected to the printer (a "station"). Nothing is shown to users: a phone becomes a station by connecting to the printer.
//
// Standard Cloudflare pattern: a Durable Object with SQLite storage (so the queue survives restarts) and hibernating WebSockets
// (the station keeps one open connection and the server pushes jobs down it; nobody polls).
//   enqueue  : POST /enqueue            a receipt to print (a repeated `key` is ignored, so a retry never prints twice)
//   station  : GET  /station (upgrade)  a phone that has the printer connected
// Station protocol (JSON text): server -> {"type":"job","id":N,"data":{...}}   station -> {"type":"done","id":N} | {"type":"failed","id":N}
// One job per station at a time, oldest first. A job whose station disappears is handed to another station (or waits for one).
import { DurableObject } from "cloudflare:workers";
import type { Bindings } from "./types";

const MAX_TRIES = 3; // a receipt that keeps failing is dropped (printer out of paper, etc.), not retried forever
const EXPIRE_MS = 2 * 3600_000; // a receipt nobody printed within 2 hours is dropped, so an old queue never prints at a later event
const STALE_MS = 90_000; // a station that took a job and never answered (phone died) loses it after this long

type JobRow = { id: number; data: string; tries: number; sent_to: string | null; sent_at: number | null };

export class PrintHub extends DurableObject<Bindings> {
  private sql = this.ctx.storage.sql;

  constructor(ctx: DurableObjectState, env: Bindings) {
    super(ctx, env);
    this.sql.exec(`CREATE TABLE IF NOT EXISTS jobs (
      id INTEGER PRIMARY KEY AUTOINCREMENT, key TEXT UNIQUE NOT NULL, data TEXT NOT NULL, created INTEGER NOT NULL,
      tries INTEGER NOT NULL DEFAULT 0, sent_to TEXT, sent_at INTEGER)`);
  }

  async fetch(req: Request): Promise<Response> {
    const path = new URL(req.url).pathname;
    if (path === "/station" && req.headers.get("Upgrade") === "websocket") {
      const [client, server] = Object.values(new WebSocketPair());
      this.ctx.acceptWebSocket(server);
      server.serializeAttachment({ id: crypto.randomUUID() });
      this.dispatch();
      return new Response(null, { status: 101, webSocket: client });
    }
    if (path === "/enqueue" && req.method === "POST") {
      const { key, data } = (await req.json()) as { key: string; data: unknown };
      this.sql.exec("INSERT OR IGNORE INTO jobs (key, data, created) VALUES (?, ?, ?)", key, JSON.stringify(data), Date.now());
      this.dispatch();
      return Response.json({ stations: this.ctx.getWebSockets().length });
    }
    return new Response("Not found", { status: 404 });
  }

  /** Gives the oldest waiting job to every station that is idle. */
  private dispatch() {
    const now = Date.now();
    this.sql.exec("DELETE FROM jobs WHERE sent_to IS NULL AND created < ?", now - EXPIRE_MS);
    for (const ws of this.ctx.getWebSockets()) {
      const id = (ws.deserializeAttachment() as { id: string } | null)?.id;
      if (!id) continue;
      if (this.sql.exec("SELECT 1 FROM jobs WHERE sent_to = ?", id).toArray().length) continue; // still printing one
      const next = this.sql.exec<JobRow>("SELECT id, data, tries, sent_to, sent_at FROM jobs WHERE sent_to IS NULL ORDER BY id LIMIT 1").toArray()[0];
      if (!next) break;
      try {
        ws.send(JSON.stringify({ type: "job", id: next.id, data: JSON.parse(next.data) }));
        this.sql.exec("UPDATE jobs SET sent_to = ?, sent_at = ? WHERE id = ?", id, now, next.id);
        void this.ctx.storage.setAlarm(now + STALE_MS + 5000);
      } catch {
        /* this socket is already gone; the close event will follow */
      }
    }
  }

  /** Puts jobs back in the queue (a station left, or never answered). Too many failures drop the job. */
  private requeue(where: string, params: unknown[]) {
    this.sql.exec(`UPDATE jobs SET tries = tries + 1, sent_to = NULL, sent_at = NULL WHERE ${where}`, ...params);
    this.sql.exec("DELETE FROM jobs WHERE tries >= ?", MAX_TRIES);
  }

  webSocketMessage(ws: WebSocket, message: string | ArrayBuffer) {
    const id = (ws.deserializeAttachment() as { id: string } | null)?.id;
    let m: { type?: string; id?: number } = {};
    try { m = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message)); } catch { return; }
    if (!id || typeof m.id !== "number") return;
    if (m.type === "done") {
      this.sql.exec("DELETE FROM jobs WHERE id = ? AND sent_to = ?", m.id, id);
    } else if (m.type === "failed") {
      this.requeue("id = ? AND sent_to = ?", [m.id, id]);
      ws.close(1000, "printer error"); // this phone's printer is not working; let another station take over
    }
    this.dispatch();
  }

  webSocketClose(ws: WebSocket) {
    const id = (ws.deserializeAttachment() as { id: string } | null)?.id;
    if (id) this.requeue("sent_to = ?", [id]);
    this.dispatch();
  }

  webSocketError(ws: WebSocket) {
    this.webSocketClose(ws);
  }

  alarm() {
    this.requeue("sent_to IS NOT NULL AND sent_at < ?", [Date.now() - STALE_MS]);
    this.dispatch();
  }
}
