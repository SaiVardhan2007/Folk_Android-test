import { requireSession } from "@/lib/auth";
import { AppShell } from "@/components/app-shell";

// Every page inside app/(app)/ gets the sidebar + header and requires sign-in.
// (Server actions and route handlers must still call requireSession() themselves.)
export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const session = await requireSession();
  return <AppShell name={session.name} mob={session.mob} tag={session.tag}>{children}</AppShell>;
}
