# Adding pages and features

```
app/
  (auth)/login/          public sign-in page
  (app)/                 everything here needs sign-in and gets the sidebar layout
    layout.tsx           sign-in check + app shell (sidebar / tab bar)
    page.tsx             Home
    attendance/  register/  reports/     one folder per feature
  api/export/[type]/     CSV download (checks sign-in itself)
components/              shared UI (app-shell, page-header, registration-fields, ...)
components/ui/           shadcn/ui building blocks (add more with `npx shadcn@latest add <name>`)
lib/nav.ts               the menu: one line per page
lib/erpnext/             one file per DocType (client.ts = shared helpers)
lib/services/            business rules used by several features
```

## Add a page in 3 steps
1. Create `app/(app)/<name>/page.tsx`. Start it with `<PageHeader title="..." />`.
2. Add one line to `NAV` in `lib/nav.ts`. It appears in the sidebar and on Home.
   Set `mobile: true` to also show it in the phone tab bar (keep that to 4 or fewer).
3. For data, add a file in `lib/erpnext/` (use `list`, `count`, `erp` from `client.ts`) and export it from `lib/erpnext/index.ts`.

## Rules to keep it safe
- Server actions (`"use server"`) and route handlers must call `requireSession()` / `getSession()` themselves.
  The layout check only covers page rendering.
- ERPNext is only called from server code. Never import `lib/erpnext` values into a `"use client"` file
  (types are fine). Shared constants for both sides live in plain files like `lib/levels.ts`.
- Put logic used by more than one feature in `lib/services/`.

## Back button / PWA rule
Every screen a user can reach must be a real route, so Back never closes the installed app.
- Sub-steps get their own page, for example `/attendance/[mob]`. Use `<PageHeader backHref="..." />`.
- Filters that change what's shown live in the URL (`?event=...`). Use `router.replace` for these, so they don't fill up history.
- After a form succeeds on its own page, use `router.replace(...)` to leave it.
- The app opens at `/` (Home).
