// Small chart pieces in plain HTML (no chart library): stat tiles, ranked bars, a breakdown table.
// Colors come from --viz-1..3 (light and dark values live in globals.css). Text always uses text tokens, never a series color.
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import type { Count, Row } from "@/lib/erpnext";

export function StatTile({ label, value, hint }: { label: string; value: string | number; hint?: string }) {
  return (
    <Card size="sm">
      <CardHeader>
        <CardDescription>{label}</CardDescription>
        <p className="font-display text-3xl font-semibold leading-none tabular-nums text-primary dark:text-foreground">{value}</p>
        {hint && <p className="text-xs text-muted-foreground">{hint}</p>}
      </CardHeader>
    </Card>
  );
}

export function Panel({ title, description, children, className }: { title: string; description?: string; children: React.ReactNode; className?: string }) {
  return (
    <Card className={className}>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        {description && <CardDescription>{description}</CardDescription>}
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}

export const Empty = ({ children = "No data for these filters." }: { children?: React.ReactNode }) => <p className="py-6 text-center text-sm text-muted-foreground">{children}</p>;

/** Horizontal ranked bars with the value printed at the end of each bar. */
export function BarList({ items, unit = "" }: { items: Count[]; unit?: string }) {
  const max = Math.max(1, ...items.map((i) => i.value));
  if (!items.some((i) => i.value)) return <Empty />;
  return (
    <ul className="space-y-3">
      {items.map((i) => (
        <li key={i.label + (i.hint ?? "")} className="space-y-1" title={`${i.label}: ${i.value}${unit}`}>
          <div className="flex items-baseline justify-between gap-3 text-sm">
            <span className="min-w-0 truncate">{i.label}{i.hint && <span className="ml-2 text-xs text-muted-foreground">{i.hint}</span>}</span>
            <span className="shrink-0 font-medium tabular-nums">{i.value}{unit}</span>
          </div>
          <div className="h-2 rounded-full bg-muted"><div className="h-full rounded-r-[4px] rounded-l-full bg-viz-1" style={{ width: `${(i.value / max) * 100}%` }} /></div>
        </li>
      ))}
    </ul>
  );
}

/** Group table: people, unique attended, check-ins and an attendance-rate meter. On phones it drops the check-ins column and the meter (the % stays), so it fits without scrolling. */
export function BreakdownTable({ rows, firstColumn }: { rows: Row[]; firstColumn: string }) {
  if (!rows.length) return <Empty />;
  return (
    <div className="-mx-2 overflow-x-auto px-2">
      <table className="w-full text-left text-sm">
        <thead className="text-xs text-muted-foreground">
          <tr><th className="py-2 pr-3 font-medium">{firstColumn}</th><th className="px-3 py-2 text-right font-medium">People</th><th className="px-3 py-2 text-right font-medium">Attended</th><th className="hidden px-3 py-2 text-right font-medium sm:table-cell">Check-ins</th><th className="w-20 py-2 pl-3 font-medium sm:w-36">Rate</th></tr>
        </thead>
        <tbody>
          {rows.map((r) => {
            const rate = r.people ? Math.min(100, Math.round((100 * r.attended) / r.people)) : 0;
            return (
              <tr key={r.key} className="border-t">
                <td className="py-2.5 pr-3 font-medium">{r.key}</td>
                <td className="px-3 py-2.5 text-right tabular-nums">{r.people}</td>
                <td className="px-3 py-2.5 text-right tabular-nums">{r.attended}</td>
                <td className="hidden px-3 py-2.5 text-right tabular-nums sm:table-cell">{r.checkins}</td>
                <td className="py-2.5 pl-3">
                  <div className="flex items-center gap-2" title={`${rate}% of ${r.people}`}>
                    <div className="hidden h-2 flex-1 rounded-full bg-muted sm:block"><div className="h-full rounded-r-[4px] rounded-l-full bg-viz-1" style={{ width: `${rate}%` }} /></div>
                    <span className="w-9 text-right text-xs tabular-nums text-muted-foreground">{rate}%</span>
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
