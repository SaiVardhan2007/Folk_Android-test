"use client";
import { useTransition } from "react";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { genderLabel } from "@/lib/genders";
import type { Person } from "@/lib/erpnext";
import type { Result } from "@/lib/result";
import { MAIN_ADMIN_MOB } from "@/lib/roles";
import { resetPasswordAction, setTagAction } from "./actions";

function Row({ p, isMe, tags }: { p: Person; isMe: boolean; tags: string[] }) {
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
          {pending && <Loader2 className="size-4 animate-spin text-muted-foreground" aria-label="Saving" />}
          {!p.has_password && <Badge variant="secondary">No password yet</Badge>}
          {p.has_password && !isMe && (
            <Button variant="outline" size="sm" disabled={pending} onClick={() => { if (confirm(`Clear ${p.full_name}'s password?`)) run(() => resetPasswordAction(p.mob_no)); }}>
              {pending && <Loader2 className="animate-spin" />} Reset password
            </Button>
          )}
          <select value={p.user_tag} disabled={pending || isMe || p.mob_no === MAIN_ADMIN_MOB} aria-label="User tag" title={isMe ? "You can't change your own tag" : p.mob_no === MAIN_ADMIN_MOB ? "The main admin can only be changed in ERPNext" : undefined}
            onChange={(e) => run(() => setTagAction(p.mob_no, e.target.value))}
            className="h-9 rounded-md border bg-background px-2 text-sm disabled:opacity-60">
            {tags.map((t) => <option key={t}>{t}</option>)}
          </select>
        </div>
      </CardContent>
    </Card>
  );
}

export function PeopleList({ people, myMob, tags }: { people: Person[]; myMob: string; tags: string[] }) {
  return <div className="space-y-3">{people.map((p) => <Row key={p.mob_no} p={p} isMe={p.mob_no === myMob} tags={tags} />)}</div>;
}
