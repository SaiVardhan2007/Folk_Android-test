import { requireAdmin } from "@/lib/auth";
import { PageHeader } from "@/components/page-header";
import { AdminTabs } from "./admin-tabs";

// Every page under /admin is Admin-only. (Server actions and route handlers still call requireAdmin() themselves.)
export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await requireAdmin();
  return (
    <>
      <PageHeader title="Admin" description="Manage people and see how the programme is doing." />
      <AdminTabs />
      {children}
    </>
  );
}
