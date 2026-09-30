"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { BarChart3, Users } from "lucide-react";
import { cn } from "@/lib/utils";

const TABS = [
  { href: "/admin", label: "People", icon: Users },
  { href: "/admin/analytics", label: "Analytics", icon: BarChart3 },
];

export function AdminTabs() {
  const path = usePathname();
  return (
    <nav aria-label="Admin sections" className="mb-6 flex gap-1 rounded-xl bg-muted p-1">
      {TABS.map(({ href, label, icon: Icon }) => (
        <Link key={href} href={href} aria-current={path === href ? "page" : undefined}
          className={cn("flex flex-1 items-center justify-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-muted-foreground transition-colors hover:text-foreground", path === href && "bg-card text-foreground shadow-sm")}>
          <Icon className="size-4" /> {label}
        </Link>
      ))}
    </nav>
  );
}
