import type { Metadata } from "next";
import { currentEvent, listEvents } from "@/lib/erpnext";
import { PageHeader } from "@/components/page-header";
import { RegisterForm } from "./register-form";

export const metadata: Metadata = { title: "Register" };
export const dynamic = "force-dynamic";

export default async function RegisterPage() {
  const [events, current] = await Promise.all([listEvents(), currentEvent()]);
  return (
    <>
      <PageHeader title="New registration" description="Only the essentials. Mobile number must be unique." />
      <RegisterForm events={events} initialEvent={current ?? ""} />
    </>
  );
}
