/* eslint-disable @next/next/no-img-element -- a plain <img> keeps this working on Cloudflare without an image-optimisation binding */
import { cn } from "@/lib/utils";

/** The FOLK logo (public/logo.png, black lettering on a transparent background).
 *  On dark surfaces pass `tile` to sit it on a white rounded tile so the lettering stays readable. */
export function Logo({ className, tile }: { className?: string; tile?: boolean }) {
  const img = <img src="/logo.png" width={256} height={173} alt="FOLK, Friends of Lord Krishna" className={cn("h-auto w-auto", !tile && className)} />;
  return tile ? <span className={cn("inline-flex items-center justify-center rounded-lg bg-white p-1", className)}>{img}</span> : img;
}
