"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { LogOut, User } from "lucide-react";
import { navFor } from "@/lib/nav";
import { cn } from "@/lib/utils";
import { BrandMark } from "@/components/brand-mark";
import { Button } from "@/components/ui/button";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { logoutAction } from "@/app/(app)/actions";

// `className` lets each placement size the trigger: full width in the sidebar, natural width in the phone header.
function UserMenu({ name, mob, tag, className }: { name: string; mob: string; tag: string; className?: string }) {
  return (
    <DropdownMenu>
      <DropdownMenuTrigger render={<Button variant="ghost" size="sm" className={cn("gap-2 text-sidebar-foreground hover:bg-sidebar-accent hover:text-sidebar-foreground", className)} />}>
        <User className="shrink-0" /> <span className="max-w-32 truncate">{name}</span>
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end" className="w-56">
        <DropdownMenuLabel className="font-normal"><div className="font-medium">{name} <span className="text-xs font-normal text-muted-foreground">· {tag}</span></div><div className="truncate text-xs text-muted-foreground">{mob}</div></DropdownMenuLabel>
        <DropdownMenuSeparator />
        <DropdownMenuItem onClick={() => logoutAction()}><LogOut /> Log out</DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}

/** Page frame: sidebar on desktop; top bar + bottom tab bar on phones. Menu items come from lib/nav.ts. */
export function AppShell({ name, mob, tag, children }: { name: string; mob: string; tag: string; children: React.ReactNode }) {
  const path = usePathname();
  const NAV = navFor(tag);
  const active = (href: string) => (href === "/" ? path === "/" : path.startsWith(href));

  const Brand = (
    <Link href="/" className="flex shrink-0 items-center gap-2.5 font-display text-lg font-semibold tracking-tight">
      <BrandMark className="size-8" />
      FOLK Tracker
    </Link>
  );

  return (
    <div className="min-h-screen overflow-x-clip md:pl-60">
      {/* desktop sidebar */}
      <aside className="fixed inset-y-0 left-0 z-30 hidden w-60 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground md:flex">
        <div className="flex h-16 items-center border-b border-sidebar-border px-5">{Brand}</div>
        <nav className="flex-1 space-y-1 p-3">
          {NAV.map(({ href, label, icon: Icon }) => (
            <Link key={href} href={href}
              className={cn("flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-foreground", active(href) && "bg-sidebar-accent text-sidebar-primary")}>
              <Icon className="size-4" /> {label}
            </Link>
          ))}
        </nav>
        <div className="border-t border-sidebar-border p-3"><UserMenu name={name} mob={mob} tag={tag} className="w-full justify-start" /></div>
      </aside>

      {/* mobile top bar */}
      <header className="sticky top-0 z-30 flex h-14 items-center justify-between gap-2 bg-sidebar px-4 text-sidebar-foreground md:hidden">
        {Brand}<UserMenu name={name} mob={mob} tag={tag} className="min-w-0 shrink" />
      </header>

      <main className="mx-auto w-full max-w-3xl px-4 py-8 pb-28 md:px-8 md:pb-10">{children}</main>

      {/* mobile bottom tab bar */}
      <nav className="fixed inset-x-0 bottom-0 z-30 flex border-t bg-card/95 pb-[env(safe-area-inset-bottom)] backdrop-blur md:hidden">
        {NAV.filter((n) => n.mobile).map(({ href, label, icon: Icon }) => (
          <Link key={href} href={href}
            className={cn("flex flex-1 flex-col items-center gap-1 py-2.5 text-xs font-medium text-muted-foreground", active(href) && "text-primary [&_svg]:fill-gold/30")}>
            <Icon className="size-5" /> {label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
