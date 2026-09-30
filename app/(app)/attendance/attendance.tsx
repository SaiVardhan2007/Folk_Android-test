"use client";
import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Search, Undo2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Skeleton } from "@/components/ui/skeleton";
import {
  AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent,
  AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import type { AttendanceRow, Event } from "@/lib/erpnext";
import { EventSelect } from "@/components/event-select";
import { todayListAction, undoAction } from "./actions";

const POLL_MS = 5000;

/** Search screen. Typing 10 digits opens /attendance/<mobile> (a real page, so Back returns here). */
export default function Attendance({ events, event }: { events: Event[]; event: string }) {
  const router = useRouter();
  const [mob, setMob] = useState("");
  const [today, setToday] = useState<AttendanceRow[] | null>(null);
  const [undoRow, setUndoRow] = useState<AttendanceRow | null>(null);
  const [pending, start] = useTransition();

  const digits = mob.replace(/\D/g, "").replace(/^91(?=\d{10}$)/, "");

  // auto-open the result page once 10 digits are entered (debounced)
  useEffect(() => {
    if (digits.length !== 10) return;
    const t = setTimeout(() => router.push(`/attendance/${digits}?event=${encodeURIComponent(event)}`), 300);
    return () => clearTimeout(t);
  }, [digits, event, router]);

  // "live" list: poll every few seconds while the tab is visible
  const refresh = () => todayListAction(event).then(setToday).catch(() => {});
  useEffect(() => {
    refresh();
    const id = setInterval(() => { if (!document.hidden) refresh(); }, POLL_MS);
    return () => clearInterval(id);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [event]);

  function confirmUndo() {
    const row = undoRow;
    setUndoRow(null);
    if (!row) return;
    start(async () => {
      const r = await undoAction(row.mob_no, row.name);
      if (r.ok) toast.success(`Undone for ${row.attendee_name}`);
      else toast.error(r.message);
      refresh();
    });
  }

  return (
    <div className="space-y-6">
      <Card>
        <CardContent className="space-y-4">
          <EventSelect events={events} value={event} onChange={(v) => router.replace(`/attendance?event=${encodeURIComponent(v)}`)} />
          <div className="relative">
            <Search className="pointer-events-none absolute left-3 top-1/2 size-5 -translate-y-1/2 text-muted-foreground" />
            <Input type="tel" inputMode="numeric" autoFocus autoComplete="off" placeholder="Mobile number"
              className="h-12 pl-10 text-lg tracking-wide" value={mob} onChange={(e) => setMob(e.target.value)} />
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="flex items-center justify-between text-base">
            Today&apos;s attendance <Badge variant="secondary">{today?.length ?? "…"}</Badge>
          </CardTitle>
          <CardDescription>Updates automatically. Newest first.</CardDescription>
        </CardHeader>
        <CardContent>
          {today === null ? (
            <div className="space-y-2">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-14 w-full" />)}</div>
          ) : today.length === 0 ? (
            <p className="py-6 text-center text-sm text-muted-foreground">No one marked yet.</p>
          ) : (
            <ul className="divide-y">
              {today.map((r) => (
                <li key={r.name} className="flex items-center justify-between gap-3 py-3">
                  <div className="min-w-0">
                    <p className="truncate font-medium">{r.attendee_name || r.mob_no}</p>
                    <p className="text-sm text-muted-foreground">{r.mob_no} · {r.ts?.slice(11, 16)} · {r.marked_by}</p>
                  </div>
                  <Button variant="ghost" size="sm" disabled={pending} onClick={() => setUndoRow(r)}>
                    <Undo2 /> Undo
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </CardContent>
      </Card>

      <AlertDialog open={!!undoRow} onOpenChange={(o) => !o && setUndoRow(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Undo attendance?</AlertDialogTitle>
            <AlertDialogDescription>
              This removes today&apos;s attendance for {undoRow?.attendee_name} ({undoRow?.mob_no}).
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep</AlertDialogCancel>
            <AlertDialogAction variant="destructive" onClick={confirmUndo}>Undo attendance</AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  );
}
