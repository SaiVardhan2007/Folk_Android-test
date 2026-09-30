// Small helpers shared by server and client code.
export { cn } from "cn"; // joins class names (Tailwind helper)

const TZ = "Asia/Kolkata";

/** All dates/times in the app are India time, whatever the server's timezone is. */
export const todayIST = () => new Date().toLocaleDateString("en-CA", { timeZone: TZ });
export const nowIST = () => new Date().toLocaleString("sv-SE", { timeZone: TZ }); // YYYY-MM-DD HH:mm:ss

/** "+91 98765-43210" -> "9876543210"; null if not a valid 10-digit number. */
export function normalizeMobile(raw: string) {
  let d = raw.replace(/\D/g, "");
  if (d.length === 12 && d.startsWith("91")) d = d.slice(2);
  return /^\d{10}$/.test(d) ? d : null;
}

/** Rows -> CSV text with a header line. Quotes any cell containing a comma, quote or newline. */
export function toCsv(rows: Record<string, unknown>[], cols: string[]) {
  const esc = (v: unknown) => {
    const s = String(v ?? "");
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  return [cols.join(","), ...rows.map((r) => cols.map((c) => esc(r[c])).join(","))].join("\n");
}
