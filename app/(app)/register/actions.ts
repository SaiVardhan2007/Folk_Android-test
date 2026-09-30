"use server";

import { requireSession } from "@/lib/auth";
import type { Result } from "@/lib/result";
import { createRegistrationChecked, readRegistrationFields } from "@/lib/services/registration";

export async function registerAction(form: FormData): Promise<Result> {
  const who = await requireSession();
  const f = readRegistrationFields(form);
  try {
    const err = await createRegistrationChecked(f, who.name);
    return err ?? { ok: true, message: `Registered ${f.full_name} (${f.mob_no}).` };
  } catch (e) {
    console.error(e);
    return { ok: false, message: "Could not save to ERPNext. Try again." };
  }
}
