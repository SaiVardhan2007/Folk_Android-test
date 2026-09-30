import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

const control = "h-10 w-full rounded-lg border border-input bg-background px-3 text-sm outline-none transition-colors focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/40";

/** Label + control for GET filter forms. Plain HTML controls, so they work without client JS. */
export function FilterField({ label, children, className }: { label: string; children: React.ReactNode; className?: string }) {
  return (
    <label className={cn("block space-y-1.5", className)}>
      <span className="text-xs font-medium text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}

export function FilterSelect({ name, value, options, any = "Any" }: { name: string; value: string; options: readonly (string | { value: string; label: string })[]; any?: string }) {
  return (
    <select name={name} defaultValue={value} className={control}>
      {any && <option value="">{any}</option>}
      {options.map((o) => { const v = typeof o === "string" ? o : o.value; return <option key={v} value={v}>{typeof o === "string" ? o : o.label}</option>; })}
    </select>
  );
}

export function FilterInput(props: React.ComponentProps<"input">) {
  return <input {...props} className={cn(control, props.className)} />;
}

const pill = "h-9 rounded-full border bg-background pl-3 pr-2 text-sm outline-none transition-colors focus-visible:ring-3 focus-visible:ring-ring/40";

/** Compact dropdown for filter rows. The first option is the label ("Tag", "Level"…); it turns solid when a value is picked. */
export function FilterPill({ name, label, value, options }: { name: string; label: string; value: string; options: readonly (string | { value: string; label: string })[] }) {
  return (
    <span className="relative inline-flex shrink-0 items-center">
      <select name={name} defaultValue={value} aria-label={label} className={cn(pill, "appearance-none pr-8", value ? "border-primary bg-primary text-primary-foreground" : "text-muted-foreground")}>
        <option value="">{label}</option>
        {options.map((o) => { const v = typeof o === "string" ? o : o.value; return <option key={v} value={v}>{typeof o === "string" ? o : o.label}</option>; })}
      </select>
      <ChevronDown className={cn("pointer-events-none absolute right-2.5 size-4", value ? "text-primary-foreground" : "text-muted-foreground")} aria-hidden />
    </span>
  );
}

/** Small date input for filter rows. */
export function FilterDate({ name, label, value, max }: { name: string; label: string; value: string; max?: string }) {
  return (
    <label className="relative flex shrink-0 items-center gap-1.5">
      <span className="sr-only">{label}</span>
      <input type="date" name={name} defaultValue={value} max={max} aria-label={label} title={label} className={cn(pill, "pr-2", value ? "border-primary text-foreground" : "text-muted-foreground")} />
    </label>
  );
}
