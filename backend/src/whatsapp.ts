// WhatsApp messages. Only two are ever sent:
//  1. welcome  -> the contact, when they are created or registered for an event
//  2. attendance alert -> the coordinator(s) assigned to that contact, when their attendance is marked
import type { Bindings } from "./types";

export type TemplateMessage = { to: string; template: string; params: string[] };
type ContactLike = { mob_no: string; full_name: string; venue?: string; guide_mobile?: string | null };

const text = (v: unknown, fallback = "-") => {
  const s = v === undefined || v === null ? "" : String(v).trim();
  return s || fallback; // WhatsApp rejects empty template parameters
};
/** WhatsApp needs the country code: a 10-digit Indian number becomes 91XXXXXXXXXX. */
const wa = (n: string) => (/^\d{10}$/.test(n) ? `91${n}` : n.replace(/\D/g, ""));

/** Used in the welcome message when the contact has no venue / map link / FOLK guide number of their own. */
export type Defaults = { venue?: string; map?: string; guideMob?: string };
export const defaultsOf = (env: Bindings): Defaults => ({ venue: env.WELCOME_VENUE, map: env.WELCOME_MAP_LINK, guideMob: env.DEFAULT_GUIDE_MOB });

/** The welcome message for a contact who was just created or registered for an event. It goes to that contact only. */
export function welcomeMessage(p: ContactLike, eventName: string, welcomeTemplate = "event_registration", d: Defaults = {}): TemplateMessage | null {
  if (!p.mob_no) return null;
  return { to: wa(p.mob_no), template: welcomeTemplate, params: [text(p.full_name, "Friend"), text(eventName), text(p.venue || d.venue), text(d.map), text(p.guide_mobile || d.guideMob)] };
}

export async function sendTemplate(env: Bindings, m: TemplateMessage): Promise<boolean> {
  const res = await fetch(env.WHATSAPP_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      apikey: env.WHATSAPP_API_KEY,
      phone_number_id: env.WHATSAPP_PHONE_NUMBER_ID,
      body: {
        messaging_product: "whatsapp", to: m.to, type: "template",
        template: { name: m.template, language: { code: "en_US" }, components: [{ type: "body", parameters: m.params.map((t) => ({ type: "text", text: t })) }] },
      },
    }),
  });
  const raw = await res.text();
  // This provider answers HTTP 200 even when WhatsApp rejects the message; the rejection is inside the body.
  let rejected = "";
  try {
    const j = JSON.parse(raw) as { status?: string; data?: { error?: { message?: string } }; error?: unknown; message?: string };
    if (j.data?.error) rejected = j.data.error.message ?? "rejected";
    else if (j.error || (j.status && j.status !== "success")) rejected = String(j.message ?? JSON.stringify(j.error ?? j.status)).slice(0, 200);
  } catch { /* not JSON: judged by the HTTP status alone */ }
  const ok = res.ok && !rejected;
  console.log(`whatsapp ${m.template} to ${m.to} -> ${ok ? "sent" : "FAILED"} (${res.status}) ${rejected || raw.slice(0, 200)}`);
  return ok;
}

/**
 * Alert to a coordinator when a contact they were assigned attends. It reuses the approved welcome template
 * (5 fields): {{1}} the coordinator's name, {{2}} "<contact> (<phone>) attended <event> at <time>", then venue, map link, FOLK guide number.
 */
export function attendanceAlert(co: { mob_no: string; full_name: string }, person: { full_name: string; mob_no: string }, eventName: string, time: string, template: string, d: Defaults = {}): TemplateMessage {
  const what = `${text(person.full_name, "Friend")} (${text(person.mob_no)}) attended ${text(eventName, "the event")} at ${text(time)}`;
  return { to: wa(co.mob_no), template, params: [text(co.full_name, "Coordinator"), what, text(d.venue), text(d.map), text(d.guideMob)] };
}
