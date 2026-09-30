"use client";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import type { Registration } from "@/lib/erpnext";
import { GENDERS } from "@/lib/genders";
import { LEVELS } from "@/lib/levels";

const LEVEL_ITEMS = LEVELS.map((l) => ({ value: l, label: l }));

function Field({ id, label, children }: { id: string; label: string; children: React.ReactNode }) {
  return <div className="space-y-2"><Label htmlFor={id}>{label}</Label>{children}</div>;
}

/** The registration fields, shared by the Register and Attendance screens. */
export function RegistrationFields({ v = {}, mobile, lockMobile = false }: { v?: Partial<Registration>; mobile?: string; lockMobile?: boolean }) {
  return (
    <div className="space-y-4">
      <Field id="mob_no" label="Mobile number *">
        <Input id="mob_no" name="mob_no" type="tel" inputMode="numeric" maxLength={14} required className="h-10"
          placeholder="10-digit number" readOnly={lockMobile} defaultValue={mobile ?? v.mob_no ?? ""} />
      </Field>
      <Field id="full_name" label="Name *">
        <Input id="full_name" name="full_name" required className="h-10" autoComplete="off" defaultValue={v.full_name ?? ""} />
      </Field>
      <div className="grid gap-4 sm:grid-cols-2">
        <Field id="gender" label="Gender">
          <Select name="gender" items={GENDERS} defaultValue={v.gender || null}>
            <SelectTrigger id="gender" className="h-10 w-full"><SelectValue placeholder="Select gender" /></SelectTrigger>
            <SelectContent>{GENDERS.map((g) => <SelectItem key={g.value} value={g.value}>{g.label}</SelectItem>)}</SelectContent>
          </Select>
        </Field>
        <Field id="level" label="Level *">
          <Select name="level" items={LEVEL_ITEMS} defaultValue={v.level || null}>
            <SelectTrigger id="level" className="h-10 w-full"><SelectValue placeholder="Select level" /></SelectTrigger>
            <SelectContent>{LEVEL_ITEMS.map((l) => <SelectItem key={l.value} value={l.value}>{l.label}</SelectItem>)}</SelectContent>
          </Select>
        </Field>
      </div>
      <Field id="pg_name" label="PG / Residence name">
        <Input id="pg_name" name="pg_name" className="h-10" autoComplete="off" defaultValue={v.pg_name ?? ""} />
      </Field>
      <Field id="profession" label="Profession / Company / College">
        <Input id="profession" name="profession" className="h-10" autoComplete="off" defaultValue={v.profession ?? ""} />
      </Field>
    </div>
  );
}
