"use client";
import { useEffect, useRef, useState } from "react";
import { usePathname, useSearchParams } from "next/navigation";
import { cn } from "@/lib/utils";

const EVENT = "route-progress:start";
/** Call right before a programmatic navigation (router.push / replace) so the top bar shows immediately. */
export const startProgress = () => window.dispatchEvent(new Event(EVENT));

/** Loading feedback for every navigation. Starts the instant an internal link is clicked (or startProgress() is called)
 *  and ends when the new page arrives: a thin bar at the very top, plus the page content blurs with a loader in the middle.
 *  Mounted once in the root layout, inside <Suspense>. */
export function RouteProgress() {
  const pathname = usePathname();
  const search = useSearchParams().toString();
  const [width, setWidth] = useState(0);
  const [visible, setVisible] = useState(false);
  const [busy, setBusy] = useState(false); // drives the blur + centred loader
  const running = useRef(false);
  const timers = useRef<{ tick?: ReturnType<typeof setInterval>; fail?: ReturnType<typeof setTimeout>; hide?: ReturnType<typeof setTimeout> }>({});

  const finish = () => {
    if (!running.current) return;
    running.current = false;
    setBusy(false);
    clearInterval(timers.current.tick); clearTimeout(timers.current.fail);
    setWidth(100);
    timers.current.hide = setTimeout(() => { setVisible(false); setWidth(0); }, 250);
  };

  useEffect(() => {
    const start = () => {
      if (running.current) return;
      running.current = true;
      setBusy(true);
      clearTimeout(timers.current.hide);
      setVisible(true); setWidth(10);
      // creep towards 90% so it always looks alive, then wait for the real page
      timers.current.tick = setInterval(() => setWidth((w) => (w < 90 ? w + (90 - w) * 0.12 : w)), 200);
      timers.current.fail = setTimeout(finish, 15000); // never get stuck
    };
    const onClick = (e: MouseEvent) => {
      if (e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
      const a = (e.target as HTMLElement).closest?.("a[href]") as HTMLAnchorElement | null;
      if (!a || (a.target && a.target !== "_self") || a.hasAttribute("download")) return;
      const url = new URL(a.href, location.href);
      if (url.origin !== location.origin || (url.pathname === location.pathname && url.search === location.search)) return;
      start();
    };
    const t = timers.current;
    document.addEventListener("click", onClick, true);
    window.addEventListener(EVENT, start);
    return () => { document.removeEventListener("click", onClick, true); window.removeEventListener(EVENT, start); clearInterval(t.tick); clearTimeout(t.fail); clearTimeout(t.hide); };
  }, []);

  // the route changed: the new page is here
  useEffect(() => { finish(); }, [pathname, search]);

  return (
    <>
      <div aria-hidden className="pointer-events-none fixed inset-x-0 top-0 z-[100] h-[3px]" style={{ opacity: visible ? 1 : 0, transition: "opacity 200ms" }}>
        <div className="h-full rounded-r-full bg-gold shadow-[0_0_8px_var(--gold)]" style={{ width: `${width}%`, transition: "width 200ms ease-out" }} />
      </div>
      {/* Sits below the sidebar / header / tab bar (z-30) so they stay sharp; the page content behind it blurs. */}
      <div role="status" aria-live="polite" aria-hidden={!busy}
        className={cn("fixed inset-0 z-20 flex items-center justify-center bg-background/50 backdrop-blur-sm transition-opacity duration-200", busy ? "opacity-100" : "pointer-events-none opacity-0")}>
        {busy && <span className="sr-only">Loading</span>}
        <div className="flex flex-col items-center gap-3 rounded-2xl bg-card px-7 py-6 shadow-xl ring-1 ring-foreground/10">
          <span aria-hidden className="size-10 animate-spin rounded-full border-4 border-primary/15 border-t-gold" />
          <span aria-hidden className="text-sm font-medium text-muted-foreground">Loading…</span>
        </div>
      </div>
    </>
  );
}
