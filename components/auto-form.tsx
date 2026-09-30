"use client";
import { useTransition } from "react";
import { usePathname, useRouter } from "next/navigation";
import { cn } from "@/lib/utils";
import { startProgress } from "@/components/route-progress";

/** A filter form: re-submits when a dropdown or date changes (no Apply button) by navigating to the same page
 *  with the new query string. The top bar starts at once and the form dims while the page reloads.
 *  Text boxes are left alone (mark them data-manual) and apply on Enter. */
export function AutoForm({ children, className }: { children: React.ReactNode; className?: string }) {
  const router = useRouter();
  const path = usePathname();
  const [pending, start] = useTransition();
  return (
    <form
      aria-busy={pending}
      className={cn("transition-opacity", pending && "opacity-60", className)}
      onChange={(e) => { if (!(e.target as HTMLElement).hasAttribute("data-manual")) e.currentTarget.requestSubmit(); }}
      onSubmit={(e) => {
        e.preventDefault();
        const params = new URLSearchParams();
        for (const [k, v] of new FormData(e.currentTarget)) if (typeof v === "string" && v !== "") params.set(k, v);
        startProgress();
        start(() => router.push(params.size ? `${path}?${params}` : path));
      }}
    >
      {children}
    </form>
  );
}
