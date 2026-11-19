export type Bindings = {
  ERPNEXT_URL: string;
  ERPNEXT_API_KEY: string;
  ERPNEXT_API_SECRET: string;
  JWT_SECRET: string;
  MAIN_ADMIN_MOB: string;
  WHATSAPP_API_KEY: string;
  WHATSAPP_URL: string;
  WHATSAPP_PHONE_NUMBER_ID: string;
  /** MSG91 SMS (sign-in code). Both are Worker secrets. */
  MSG91_AUTH_KEY?: string;
  MSG91_OTP_TEMPLATE_ID?: string;
  /** "1" once the MSG91 template ends with ##hash## (lets Android read the code with no prompt). */
  OTP_SMS_HAS_APP_HASH?: string;
  /** Used in the welcome message when the contact has no venue / map link / FOLK guide number (call_no) of their own. */
  WELCOME_VENUE?: string;
  WELCOME_MAP_LINK?: string;
  DEFAULT_GUIDE_MOB?: string;
  /** The shared print queue (a Durable Object, see printHub.ts). */
  PRINT_HUB: DurableObjectNamespace;
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
export const DEFAULT_TAGS = ["Public", "Not Interested", "Coordinator", "Admin"];
/** Contacts, never app users. Only "Public" contacts are offered for calling; "Not Interested" ones are left out. */
export const NOT_INTERESTED = "Not Interested";
export const CONTACT_TAGS = ["Public", NOT_INTERESTED];
