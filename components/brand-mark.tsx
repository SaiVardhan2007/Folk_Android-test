/** Peacock-feather mark used as the app logo. */
export function BrandMark({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={className} aria-hidden>
      <path d="M32 60V40" stroke="var(--gold)" strokeWidth="3" strokeLinecap="round" fill="none" />
      <ellipse cx="32" cy="24" rx="13" ry="18" fill="var(--gold)" />
      <ellipse cx="32" cy="24" rx="10" ry="15" fill="var(--teal)" />
      <ellipse cx="32" cy="24" rx="6.5" ry="10" fill="oklch(0.38 0.1 255)" />
      <ellipse cx="32" cy="23" rx="3" ry="5" fill="var(--gold)" />
    </svg>
  );
}
