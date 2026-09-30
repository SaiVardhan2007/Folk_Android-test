"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { CheckCircle2, Loader2, UserPlus } from "lucide-react";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { RegistrationFields } from "@/components/registration-fields";
import type { Registration } from "@/lib/erpnext";
import { markAction } from "../actions";

/** Edit-and-mark form. If the person isn't registered (`reg` is null) the same submit registers them first. */
export function MarkForm({ mob, event, reg, markedToday, backHref }: {
  mob: string; event: string; reg: Registration | null; markedToday: boolean; backHref: string;
}) {
  const router = useRouter();
  const [pending, start] = useTransition();
  const isNew = !reg;

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    start(async () => {
      const r = await markAction(form);
      if (!r.ok) {
        toast.error(r.message);
        return;
      }
      toast.success(r.message);
      router.replace(backHref); // replace: Back won't return to a form that's already been submitted
    });
  }

  return (
    <Card>
      <CardContent>
        <form onSubmit={submit} className="space-y-4">
          <input type="hidden" name="event_code" value={event} />
          <input type="hidden" name="is_new" value={isNew ? "1" : "0"} />
          <div className="flex flex-wrap items-center gap-2">
            {isNew
              ? <Badge variant="secondary"><UserPlus className="size-3" /> Not registered yet</Badge>
              : <Badge variant="secondary">Registered · attended {reg.attendance_count ?? 0}×</Badge>}
            {markedToday && <Badge className="bg-teal text-white"><CheckCircle2 className="size-3" /> Marked today</Badge>}
          </div>
          <RegistrationFields v={reg ?? {}} mobile={mob} lockMobile />
          {markedToday
            ? <Button type="button" size="lg" className="h-11 w-full" disabled><CheckCircle2 /> Already Marked</Button>
            : <Button type="submit" size="lg" className="h-11 w-full" disabled={pending}>
                {pending && <Loader2 className="animate-spin" />}
                {isNew ? "Register & Mark Attendance" : "Mark Attendance"}
              </Button>}
        </form>
      </CardContent>
    </Card>
  );
}
