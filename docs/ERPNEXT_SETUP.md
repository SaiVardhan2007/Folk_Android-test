# ERPNext setup guide (do these once)

The website stores everything in ERPNext through 3 DocTypes (an ERPNext "table" with a form), plus one embedded table.

| DocType | What it stores |
|---|---|
| **FOLK Users** | one record per person: the ID is the 10-digit mobile number. It holds their details, level, tag (People / Coordinator / Admin), password hash **and their attendance** |
| **FOLK Users Attendance** | not a list of its own: it is the *Attendance* table inside each FOLK Users form. One row per event per day |
| **FOLK Event** | one row per event. The ID is the code, e.g. `SUNDAY01` |
| **FOLK Settings** | a single form with **Current Event**, the default in the dropdowns |

The definitions are in `erpnext/doctypes/*.json`. `attendance_count` and `last_attended_on` are updated by the app on every mark or undo.
There is no separate volunteer list: volunteers are just FOLK Users with the Coordinator or Admin tag.


## Step 1. Get an Administrator API key (one-time, for setup only)
1. Log in to ERPNext as Administrator, open **User list**, then **Administrator**.
2. Scroll to **API Access**, then click **Generate Keys**.
3. Copy the **API Secret** shown once. The **API Key** is on the same page.

## Step 2. Create the DocTypes automatically (recommended)
1. Edit `.env.local` and fill in:
   ```
   SETUP_ERPNEXT_URL=https://your-erp-domain
   SETUP_API_KEY=...
   SETUP_API_SECRET=...
   ```
2. Run `npm run erpnext:setup`. You should see three `+ Created ...` lines
   and one for the role `FOLK Volunteer`. You can run it again safely.
3. Check in ERPNext: search **DocType List**, and you'll see the three FOLK DocTypes.

**If the script fails:** create them by hand in ERPNext (*DocType List, then New*), Custom, Module Custom.

**FOLK Users Attendance** (tick **Is Child Table**, create this one first)
`event_code` (Link to FOLK Event), `attendance_date` (Date), `ts` (Datetime), `marked_by` (Data)

**FOLK Users** (Naming: *By fieldname*, `mob_no`)
`mob_no` (Data, mandatory, unique), `full_name` (Data, mandatory), `gender` (Select: blank, M, F),
`level` (Select: blank, Folk Foundation, Folk Prelims), `pg_name` (Data), `profession` (Data),
`event_code` (Link to FOLK Event), `attendance_count` (Int, read only), `last_attended_on` (Date, read only),
`registered_by` (Data, read only), `user_tag` (Select: People, Coordinator, Admin, default People),
`password_hash` (Data, hidden, read only), `attendance` (Table, options FOLK Users Attendance)

**FOLK Event** (Naming: *By fieldname*, `code`): `code` (Data, mandatory, unique), `event_name` (Data, mandatory)

**FOLK Settings** (tick **Is Single**): `current_event` (Link to FOLK Event)

Permissions: role **System Manager** gets everything.
The app talks to ERPNext with its API user, so only System Manager permissions are defined on the DocTypes.

## Step 3. Users and roles
The app has two kinds of access. Neither needs anything beyond the FOLK DocTypes.

**a) The app's own API user** (the website talks to ERPNext with this)
1. ERPNext, **User, New**. Email: `folk-app@yourcompany.com`, User Type **System User**.
2. In *Roles*, tick **only** `FOLK Volunteer`. Save.
3. Open that user, then **API Access, Generate Keys**. Put the key and secret into `.env.local`
   as `ERPNEXT_API_KEY` and `ERPNEXT_API_SECRET`, and set `ERPNEXT_URL` and `SESSION_SECRET`
   (run `openssl rand -hex 32`).

**b) App logins are not ERPNext users.**
Anyone can use the app. The login ID is the person's **mobile number**. The first time, they choose "First time here? Create password" on the login page; the password is stored only as a PBKDF2 hash in `FOLK Users.password_hash`.
Everyone starts with tag **People**. An **Admin** (the app's *Admin* page) changes tags and can clear a forgotten password so the person can create a new one.
Make the first Admin once with `MOB=... NAME=... npm run erpnext:make-admin`, then have them create their password on the login page.

## Step 4. Create your first event and set it as current
1. ERPNext, **FOLK Event, New**. Code `SUNDAY01`, name "Sunday Program". Save.
2. Search **FOLK Settings**, set **Current Event** to `SUNDAY01`, and Save.

## Step 5. Try it locally
```
npm run dev
```
Open http://localhost:3000, sign in with your ERPNext email and password, type a new 10-digit number on the Attendance screen (it offers
"Register & Mark Attendance"), then type the same number again to see "Already Marked".

## Step 6. Deploy to Cloudflare
1. `npx wrangler login`
2. Store the secrets on Cloudflare (it asks you to paste each value):
   ```
   npx wrangler secret put ERPNEXT_URL
   npx wrangler secret put ERPNEXT_API_KEY
   npx wrangler secret put ERPNEXT_API_SECRET
   npx wrangler secret put SESSION_SECRET
   ```
3. `npm run deploy`. You'll get a `*.workers.dev` URL. Add your own domain later in the Cloudflare dashboard (*Workers, Settings, Domains*).

**AWS note:** ERPNext must be reachable from the internet over HTTPS. If your AWS security group
restricts IPs, Cloudflare Workers use changing IPs, so allow HTTPS publicly (the API key protects it),
or put ERPNext behind a Cloudflare Tunnel.
