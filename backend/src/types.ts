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
};

export type Session = { id: string; mob: string; name: string; tag: string };
export type Vars = { session: Session };

export const LEVELS = ["Folk Foundation", "Folk Prelims"] as const;
export const GENDERS = ["M", "F"] as const;
export const OCCUPATIONS = ["Student", "Job Search", "Working"] as const;
export const DEFAULT_TAGS = ["Public", "Coordinator", "Admin"];
export const MIN_PASSWORD = 8;
