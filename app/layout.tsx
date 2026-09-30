import { Suspense } from "react";
import type { Metadata, Viewport } from "next";
import { Figtree, Fraunces } from "next/font/google";
import { cn } from "@/lib/utils";
import { Toaster } from "@/components/ui/sonner";
import { RouteProgress } from "@/components/route-progress";
import RegisterSW from "./register-sw";
import "./globals.css";

const sans = Figtree({ subsets: ["latin"], variable: "--font-sans" });
const display = Fraunces({ subsets: ["latin"], variable: "--font-display" });

export const metadata: Metadata = { title: { default: "FOLK Tracker", template: "%s · FOLK Tracker" }, description: "Registration and attendance" };
export const viewport: Viewport = { width: "device-width", initialScale: 1, themeColor: "#2f3e7a" };

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={cn("font-sans", sans.variable, display.variable)}>
      <body suppressHydrationWarning className="min-h-screen bg-background text-foreground antialiased">
        <Suspense fallback={null}><RouteProgress /></Suspense>
        {children}
        <Toaster position="top-center" richColors />
        <RegisterSW />
      </body>
    </html>
  );
}
