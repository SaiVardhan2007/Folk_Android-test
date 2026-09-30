# FOLK Tracker

Next.js frontend on Cloudflare Workers, with ERPNext as the backend. Installable as a PWA.

Features: **sign-in** (mobile + password), **registration**, **attendance** (reception-style, live list, undo),
**Admin** (people list with filters, tags, password reset, current event, CSV export, analytics dashboard).
Reports (totals + CSV) are built but hidden from the menu; see the TODO in `lib/nav.ts`.

Start here: [docs/ERPNEXT_SETUP.md](docs/ERPNEXT_SETUP.md). To add pages: [docs/ADDING_FEATURES.md](docs/ADDING_FEATURES.md)

Commands: `npm run dev`, `npm run erpnext:setup`, `npm run deploy`.

## How it fits together

```
Browser ──> Next.js pages / server actions ──> lib/erpnext/* ──> ERPNext REST API
            (app/)                              (server only, holds the API key)
```

| Folder | What lives there |
| --- | --- |
| `app/(auth)/login` | Public sign-in / "create password" page |
| `app/(app)/` | Everything behind sign-in: Home, `attendance/`, `register/`, `reports/`, `admin/` (+ `admin/analytics/`) |
| `app/api/export/[type]` | CSV downloads |
| `components/` | Shared UI. `components/ui/` is shadcn (generated, don't hand-edit) |
| `lib/erpnext/` | All ERPNext access, one file per area: `client.ts` (HTTP helpers) · `registrations.ts` · `attendance.ts` · `users.ts` (login + Admin list) · `events.ts` · `analytics.ts` |
| `lib/services/` | Business rules used by more than one screen (registration checks) |
| `lib/auth.ts` | Signed-cookie session and `requireSession()` / `requireAdmin()` |
| `lib/nav.ts` | The menu: one line per page |
| `lib/levels.ts`, `roles.ts`, `genders.ts` | Fixed option lists, safe for server and client |
| `lib/admin-query.ts` | URL params -> validated People query -> ERPNext filters |
| `erpnext/doctypes/`, `scripts/` | DocType definitions and the setup / make-admin scripts |

## Conventions

- Screens that read data are server components with `export const dynamic = "force-dynamic"` (attendance data must be live).
- Writes go through `"use server"` actions in an `actions.ts` next to the page. Each one calls `requireSession()` / `requireAdmin()` itself and returns a `Result` (`lib/result.ts`).
- Filters live in the URL so views are shareable and Back works; see the Back-button rule in the docs.
- Dates and times are India time (`todayIST`, `nowIST` in `lib/utils.ts`).
