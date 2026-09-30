"use server";

import { revalidatePath } from "next/cache";
import { requireAdmin } from "@/lib/auth";
import { listEvents, resetPassword, setCurrentEvent, setTag } from "@/lib/erpnext";
import { TAGS, type Tag } from "@/lib/roles";
import type { Result } from "@/lib/result";

// Admin-only mutations. Each action re-checks requireAdmin(): the layout check doesn't cover server actions.

/** Runs a write; turns a failure into a friendly Result and refreshes the People list on success. */
async function save(fn: () => Promise<unknown>, message: string): Promise<Result> {
  try {
    await fn();
  } catch (e) {
    console.error(e);
    return { ok: false, message: "Could not save to ERPNext. Try again." };
  }
  revalidatePath("/admin");
  return { ok: true, message };
}

export async function setTagAction(mob: string, tag: string): Promise<Result> {
  const me = await requireAdmin();
  if (!(TAGS as readonly string[]).includes(tag)) return { ok: false, message: "Unknown tag." };
  if (mob === me.mob) return { ok: false, message: "You can't change your own tag." };
  return save(() => setTag(mob, tag as Tag), "Tag updated.");
}

export async function resetPasswordAction(mob: string): Promise<Result> {
  const me = await requireAdmin();
  if (mob === me.mob) return { ok: false, message: "You can't reset your own password here." };
  return save(() => resetPassword(mob), "Password cleared. They can create a new one on the login page.");
}

export async function setCurrentEventAction(event: string): Promise<Result> {
  await requireAdmin();
  const events = await listEvents();
  if (!events.some((e) => e.name === event)) return { ok: false, message: "Unknown event." };
  return save(() => setCurrentEvent(event), "Current event updated.");
}
