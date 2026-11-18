// WhatsApp template messages sent when a contact is registered (ported from the old Airtable automation).
import type { Bindings } from "./types";

export type TemplateMessage = { to: string; template: string; params: string[] };
type ContactLike = { mob_no: string; full_name: string; venue?: string; gmap_link?: string; call_no?: string; fg_name?: string; fg_mob_no?: string };

const text = (v: unknown, fallback = "-") => {
  const s = v === undefined || v === null ? "" : String(v).trim();
  return s || fallback; // WhatsApp rejects empty template parameters
};
/** WhatsApp needs the country code: a 10-digit Indian number becomes 91XXXXXXXXXX. */
const wa = (n: string) => (/^\d{10}$/.test(n) ? `91${n}` : n.replace(/\D/g, ""));

/** The messages that would be sent for this contact. Nothing is sent here. */
export function buildMessages(p: ContactLike, eventName: string, welcomeTemplate = "event_registration"): TemplateMessage[] {
  const out: TemplateMessage[] = [];
  if (p.mob_no) {
    out.push({ to: wa(p.mob_no), template: welcomeTemplate, params: [text(p.full_name, "Friend"), text(eventName), text(p.venue), text(p.gmap_link), text(p.call_no)] });
  }
  if (p.fg_mob_no) {
    out.push({ to: wa(p.fg_mob_no), template: "event_guide", params: [text(eventName, "Not Given"), text(p.full_name, "Friend"), text(p.mob_no)] });
  }
  return out;
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
  console.log(`whatsapp ${m.template} -> ${res.status} ${raw.slice(0, 200)}`);
  return res.ok;
}

/** Alert to a coordinator: {{1}} coordinator name, {{2}} contact name, {{3}} contact phone, {{4}} time attendance was marked. */
export function attendanceAlert(coordMob: string, coordName: string, name: string, mob: string, time: string, template: string): TemplateMessage {
  return { to: wa(coordMob), template, params: [text(coordName, "Coordinator"), text(name, "Friend"), text(mob), text(time)] };
}
