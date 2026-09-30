"use client";
import { useTransition } from "react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { genderLabel } from "@/lib/genders";
import { TAGS } from "@/lib/roles";
import type { Person } from "@/lib/erpnext";
import type { Result } from "@/lib/result";
import { resetPasswordAction, setTagAction } from "./actions";

function Row({ p, isMe }: { p: Person; isMe: boolean }) {
  const [pending, start] = useTransition();
  const run = (fn: () => Promise<Result>) =>
    start(async () => { const r = await fn(); if (r.ok) toast.success(r.message); else toast.error(r.message); });

  return (
    <Card>
      <CardContent className="flex flex-wrap items-center justify-between gap-x-4 gap-y-3">
        <div className="min-w-0 basis-56 flex-1">
          <p className="truncate font-medium">{p.full_name}</p>
          <p className="text-sm text-muted-foreground">{p.mob_no}{p.level && ` · ${p.level}`}{p.gender && ` · ${genderLabel(p.gender)}`}</p>
          <p className="mt-0.5 text-xs text-muted-foreground">
            Attended {p.attendance_count}×{p.last_attended_on && ` · last ${p.last_attended_on}`} · joined {p.creation}
          </p>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {!p.has_password && <Badge variant="secondary">No password yet</Badge>}
          {p.has_password && !isMe && (
            <Button variant="outline" size="sm" disabled={pending} onClick={() => { if (confirm(`Clear ${p.full_name}'s password?`)) run(() => resetPasswordAction(p.mob_no)); }}>
              Reset password
            </Button>
          )}
          <select value={p.user_tag} disabled={pending || isMe} aria-label="User tag" title={isMe ? "You can't change your own tag" : undefined}
            onChange={(e) => run(() => setTagAction(p.mob_no, e.target.value))}
            className="h-9 rounded-md border bg-background px-2 text-sm disabled:opacity-60">
            {TAGS.map((t) => <option key={t}>{t}</option>)}
          </select>
        </div>
      </CardContent>
    </Card>
  );
}

export function PeopleList({ people, myMob }: { people: Person[]; myMob: string }) {
  return <div className="space-y-3">{people.map((p) => <Row key={p.mob_no} p={p} isMe={p.mob_no === myMob} />)}</div>;
}
