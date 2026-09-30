"use client";
import { useState, useTransition } from "react";
import { Loader2 } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Label } from "@/components/ui/label";
import type { Event } from "@/lib/erpnext";
import { EventSelect } from "@/components/event-select";
import { RegistrationFields } from "@/components/registration-fields";
import { registerAction } from "./actions";

/** New-registration form. Stays on the page after success and clears itself, ready for the next person. */
export function RegisterForm({ events, initialEvent }: { events: Event[]; initialEvent: string }) {
  const [event, setEvent] = useState(initialEvent);
  const [formKey, setFormKey] = useState(0); // bump to clear the form after success
  const [error, setError] = useState<string | null>(null);
  const [pending, start] = useTransition();

  function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const form = new FormData(e.currentTarget);
    form.set("event_code", event);
    start(async () => {
      const r = await registerAction(form);
      if (r.ok) { toast.success(r.message); setError(null); setFormKey((k) => k + 1); }
      else setError(r.message);
    });
  }

  return (
    <Card>
      <CardContent>
        <form key={formKey} onSubmit={submit} className="space-y-4">
          <RegistrationFields />
          <div className="space-y-2">
            <Label>Event</Label>
            <EventSelect events={events} value={event} onChange={setEvent} />
          </div>
          {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
          <Button type="submit" size="lg" className="h-11 w-full" disabled={pending}>
            {pending && <Loader2 className="animate-spin" />} Register
          </Button>
        </form>
      </CardContent>
    </Card>
  );
}
