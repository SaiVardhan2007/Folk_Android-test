export type Bindings = {
  ERPNEXT_URL: string;
  ERPNEXT_API_KEY: string;
  ERPNEXT_API_SECRET: string;
  JWT_SECRET: string;
  MAIN_ADMIN_MOB: string;
  WHATSAPP_API_KEY: string;
  WHATSAPP_URL: string;
  WHATSAPP_PHONE_NUMBER_ID: string;
  AUTH_LIMITER?: { limit(o: { key: string }): Promise<{ success: boolean }> };
  PUBLIC_LIMITER?: { limit(o: { key: string }): Promise<{ success: boolean }> };
};

export type Session = { id: string; mob: string; name: string; tag: string };
/** Optional detail a route adds for the activity log (who did what is filled in automatically). */
export type Vars = { session: Session; actor?: Session; log?: { target?: string; details?: string } };

export const LEVELS = ["AOMC", "Folk Foundation", "Folk Prelims", "Enhance"] as const;
export const GENDERS = ["M", "F"] as const;
export const OCCUPATIONS = ["Student", "Job Search", "Working", "Business", "Others"] as const;
export const STAYS = ["With Parents", "In Hostel"] as const;
export const FEEDBACKS = ["Excellent", "Good"] as const;
export const DONATIONS = ["Pending", "Opted to Donate"] as const;
export const DEFAULT_TAGS = ["Public", "Coordinator", "Admin"];
export const MIN_PASSWORD = 8;
