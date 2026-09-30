import Link from "next/link";
import { ArrowLeft } from "lucide-react";

/** Consistent page title used by every page inside app/(app)/. Pass `backHref` on sub-pages. */
export function PageHeader({ title, description, actions, backHref }: { title: string; description?: string; actions?: React.ReactNode; backHref?: string }) {
  return (
    <div className="mb-6 flex items-start justify-between gap-4">
      <div className="flex items-start gap-3">
        {backHref && (
          <Link href={backHref} aria-label="Back" className="mt-0.5 grid size-9 shrink-0 place-items-center rounded-lg border bg-card hover:bg-accent">
            <ArrowLeft className="size-4" />
          </Link>
        )}
        <div>
          <h1 className="text-3xl font-semibold tracking-tight text-primary dark:text-foreground">{title}</h1>
          {description && <p className="mt-1 text-sm text-muted-foreground">{description}</p>}
        </div>
      </div>
      {actions}
    </div>
  );
}
