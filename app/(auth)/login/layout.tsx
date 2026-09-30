import { redirect } from "next/navigation";
import { getSession } from "@/lib/auth";

// Already signed in? Skip the login page.
export default async function LoginLayout({ children }: { children: React.ReactNode }) {
  if (await getSession()) redirect("/");
  return children;
}
