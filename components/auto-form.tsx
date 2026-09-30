"use client";

/** A GET form that re-submits when a dropdown or date changes, so filters apply without an Apply button.
 *  Text boxes are left alone (mark them data-manual) and submit on Enter as usual. */
export function AutoForm({ children, className }: { children: React.ReactNode; className?: string }) {
  return (
    <form className={className} onChange={(e) => { if (!(e.target as HTMLElement).hasAttribute("data-manual")) e.currentTarget.requestSubmit(); }}>
      {children}
    </form>
  );
}
