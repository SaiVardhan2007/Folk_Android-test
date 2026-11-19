// Sign-in codes by SMS through MSG91 (Flow API). The key and template ID are Worker secrets, never in source.
import type { Bindings } from "./types";

/**
 * Sends `otp` to a 10-digit Indian mobile using the approved template. The template has two variables:
 *   ##otp##   the 6-digit code
 *   ##hash##  the app's 11-character hash, which must be the LAST thing in the SMS. With it, Android hands the SMS straight
 *             to the app (SMS Retriever API) and the code is filled in with no "Allow" prompt. Empty when the app did not send one.
 * Returns true when MSG91 accepted it.
 */
export async function sendOtpSms(env: Bindings, mob: string, otp: string, appHash = ""): Promise<boolean> {
  if (!env.MSG91_AUTH_KEY || !env.MSG91_OTP_TEMPLATE_ID) {
    console.log("msg91 not configured");
    return false;
  }
  const res = await fetch("https://control.msg91.com/api/v5/flow", {
    method: "POST",
    headers: { accept: "application/json", authkey: env.MSG91_AUTH_KEY, "content-type": "application/json" },
    body: JSON.stringify({ template_id: env.MSG91_OTP_TEMPLATE_ID, short_url: "0", recipients: [{ mobiles: `91${mob}`, otp, hash: appHash }] }),
  });
  const raw = await res.text();
  let type = "";
  try { type = String((JSON.parse(raw) as { type?: string }).type ?? ""); } catch { /* judged by HTTP status */ }
  const ok = res.ok && type !== "error";
  console.log(`msg91 otp to ${mob} -> ${ok ? "sent" : "FAILED"} (${res.status}) ${ok ? "" : raw.slice(0, 200)}`); // the code itself is never logged
  return ok;
}
