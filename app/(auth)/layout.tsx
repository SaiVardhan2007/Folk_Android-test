export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return <main className="grid min-h-screen place-items-center bg-[radial-gradient(ellipse_at_top,var(--accent),transparent_60%)] px-4 py-10">{children}</main>;
}
