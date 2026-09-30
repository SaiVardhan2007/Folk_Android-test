// ADD A NEW PAGE: create app/(app)/<name>/page.tsx, then add one entry here.
// It then appears in the sidebar (desktop), the Home cards, and the phone tab bar if `mobile: true`.
import { CheckCircle2, Home, ShieldCheck, UserPlus, type LucideIcon } from "lucide-react";

export type NavItem = {
  href: string;
  label: string;
  description?: string; // shown on the Home cards; omit to hide the card
  icon: LucideIcon;
  mobile?: boolean; // show in the bottom tab bar (keep to 4 or fewer)
  adminOnly?: boolean; // hidden from Coordinators (the page itself must also call requireAdmin())
};

export const NAV: NavItem[] = [
  { href: "/", label: "Home", icon: Home, mobile: true },
  { href: "/attendance", label: "Attendance", description: "Mark who is present", icon: CheckCircle2, mobile: true },
  { href: "/register", label: "Register", description: "Add a new attendee", icon: UserPlus, mobile: true },
  // TODO: re-enable Reports (re-add BarChart3 to the lucide-react import)
  //   { href: "/reports", label: "Reports", description: "Totals and CSV export", icon: BarChart3, mobile: true },
  { href: "/admin", label: "Admin", description: "Tags and logins", icon: ShieldCheck, adminOnly: true },
];

export const navFor = (tag: string) => NAV.filter((n) => !n.adminOnly || tag === "Admin");
