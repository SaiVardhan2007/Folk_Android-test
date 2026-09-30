"use server";

import { requireSession } from "@/lib/auth";
import * as erp from "@/lib/erpnext";
import type { Result } from "@/lib/result";
import { createRegistrationChecked, readRegistrationFields } from "@/lib/services/registration";
import { nowIST, todayIST } from "@/lib/utils";

/** Marks attendance. When `is_new` is set, registers the person first (one action). */
export async function markAction(form: FormData): Promise<Result> {
  const who = await requireSession();
  const f = readRegistrationFields(form);
  if (!f.event_code) return { ok: false, message: "Pick an event first." };
  if (!f.mob_no) return { ok: false, message: "Enter a valid 10-digit mobile number." };
  const mob = f.mob_no;

  try {
    if (form.get("is_new") === "1") {
      const err = await createRegistrationChecked(f, who.name);
      if (err) return err;
    } else {
      // details may have been corrected on screen: only update when something changed
      const cur = await erp.getRegistration(mob);
      if (!cur) return { ok: false, message: "Registration not found." };
      if (!f.full_name) return { ok: false, message: "Name is required." };
      const changed = (["full_name", "gender", "level", "pg_name", "profession"] as const).some((k) => (cur[k] ?? "") !== f[k]);
      if (changed) await erp.updateRegistration(mob, { full_name: f.full_name, gender: f.gender, level: f.level, pg_name: f.pg_name, profession: f.profession });
    }

    const r = await erp.markAttendance(mob, { event_code: f.event_code, attendance_date: todayIST(), ts: nowIST(), marked_by: who.name });
    return r === "already" ? { ok: true, message: "✓ Already marked today." } : { ok: true, message: `✓ Marked ${f.full_name} present.` };
  } catch (e) {
    console.error(e);
    return { ok: false, message: "Could not save to ERPNext. Try again." };
  }
}

/** Today's check-ins for the live list (polled by the Attendance screen). */
export async function todayListAction(event: string) {
  await requireSession();
  return erp.todaysAttendance(event, todayIST());
}

/** Undo a mistaken mark: removes that row from the person's attendance and refreshes their count. */
export async function undoAction(mob: string, rowName: string): Promise<Result> {
  await requireSession();
  try {
    await erp.undoAttendance(mob, rowName);
    return { ok: true, message: "Undone." };
  } catch (e) {
    console.error(e);
    return { ok: false, message: "Could not undo." };
  }
}
