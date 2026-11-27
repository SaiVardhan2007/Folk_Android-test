> **Superseded (Nov 2026).** The wizard is now two steps for every flow: 1) choose the contacts (filters), 2) choose the coordinators and
> assign. No groups, no Min, no review screen, no replacing. Assigning only draws from contacts nobody has been given yet for the event
> and goes on top of what coordinators already hold; the top of step 1 shows how many contacts are not assigned yet. "How many contacts"
> caps one hand-out. A coordinator's only limit is their Max (Admin → Calls); what they already hold counts against it. The switch on each
> coordinator in Admin → Calls turns them off (hidden from assigning) and is refused while they hold calls nobody has made. "Remove all
> assigned" deletes every unstarted call for the event. The text below is the older design.

# Assign Calls: Step-by-Step Wizard (plan)

Replaces the current one-page `lib/features/admin/assign_screen.dart`. The goal is that the admin sees one question
per screen, can't jump around mid-way, and checks a full preview before anything is saved.

---

## 0. Words used on screen

| Word | Meaning |
|---|---|
| **Contact** | A person with tag *Public* who is active. Staff and *Not Interested* contacts are never included. |
| **Untouched call** | An assignment with status *Pending*: nobody has called yet. Only these can be moved or removed. |
| **Called** | Any other status. These never move and are never removed. |
| **Group** | A set of filters plus the coordinators who will get those contacts. A plan can hold many groups. |
| **Min / Max** | How many contacts a coordinator must get at least, and may get at most, *in this assignment*. If Max is blank, there is no limit. |

Rules that always apply, as they do now: women are never given calls, and contacts that have been called stay with whoever called them.

---

## 1. Start screen: "What do you want to do?"

Three big cards, one choice each:

1. **Assign calls**: the normal hand-out for an event, covering both new and old contacts.
2. **Follow-up calls**: call again the people whose last call had a chosen status. This **doesn't touch** the normal assignment.
3. **Move a coordinator's calls**: for example, a coordinator is busy or has left. Only their **untouched** calls move.

Each flow is a wizard: **Back** and **Next** at the bottom, a progress bar at the top that reads "Step 2 of 5", and no other
navigation. Closing mid-way asks "Discard this assignment?".

---

## 2. Flow A: Assign calls (5 steps)

### Step 1: Event
Choose which event these calls are for. Below the choice, show the counts for that event:
"312 already assigned, 140 untouched, 172 called".

### Step 2: Who should be called (overall filters + analytics)
This is the pool: **every contact**, including old or imported contacts added long ago, not only new registrations.

- A big live counter at the top: **"428 contacts match"**.
- A list of fields. Tap one to open its **breakdown**:
  College/Company, Branch, Level, Gender, Registered at (event), Attended (yes/no), Guide, Skill, Interest,
  Occupation, Registered between (dates), Last call status.
- The breakdown shows **only numbers, no names**. For example, for College/Company with 100 matching contacts:

  ```
  CBIT ................ 42   42%
  VNR .................. 31   31%
  Infosys .............. 12   12%
  (Empty) .............. 15   15%
  ```
- Every row has a tick box. At the top of each field there is a switch:
  **"Only the ticked ones"** or **"Everyone except the ticked ones"**.
  That switch is how the admin says "everyone except CBIT".
- Chosen filters appear as chips under the counter (for example `College: not CBIT ×`), and tapping × removes one.
- The counts update as soon as a filter changes. The app waits about 400 ms after the last tap and then makes one request, so there is no polling.

### Step 3: Groups (who gets what)
This step answers "these contacts go to these coordinators".

- The screen starts with one group, **"All matching contacts"**, which the admin can keep as it is.
- **+ Add group** opens a small sub-wizard:
  1. *Which contacts?* The same filter UI as Step 2, but inside the pool, for example College = CBIT. It shows the count and the % of the pool.
  2. *Which coordinators?* Tick one or more. Each one gets a **Min** box and a **Max** box. Max is filled from the coordinator's saved call limit and can be changed.
  3. *Same coordinator as before?* A switch. When it is on, each contact goes back to whoever called or had them earlier, as long as that coordinator is in this group and under their Max.
- Groups are listed as cards: "CBIT → Ravi, Kiran (42 contacts)".
- **Order matters.** A contact that matches two groups goes to the **first** one. Cards can be dragged to reorder.
- The last card is always **"Everyone else"**: contacts in the pool that match no group. The admin either gives it coordinators or chooses **"Leave them unassigned"**.
- One coordinator can appear in several groups, so they can get CBIT contacts and also VNR contacts.

### Step 4: Review (nothing has been saved yet)
- For each coordinator: `Ravi: +18 (min 5, max 20)`. Rows below Min show in orange.
- **Left over** (red, only when there are some): "12 contacts could not be given because every coordinator is at Max".
- **Replaced**: "95 untouched calls from the last assignment will be removed or moved". "172 called contacts stay as they are."
- A **Back** button changes any step. **Assign** saves.

### Step 5: Saving → Done
A progress bar ("Saved 300 of 428"). Saving uses the existing batches, which are safe to repeat, so a dropped connection can carry on from where it stopped.
At the end, the screen shows a summary and a **Done** button.

**What "assign again" means:** a new *Assign calls* for the same event **replaces** the earlier one. Every untouched,
non-follow-up call for that event that isn't in the new plan is removed. Called contacts are never touched.

---

## 3. How contacts are shared out (Min / Max)

The rule runs inside each group:

1. **Fill the minimums first.** Go round the coordinators one contact at a time until each one reaches their Min.
2. **Then share out evenly.** Each next contact goes to the coordinator who currently has the **fewest**, skipping anyone at Max.
3. **Stop** when there are no contacts left (done) or every coordinator is at Max. Anything still unassigned is shown as **Left over**.
4. If there aren't enough contacts to meet every Min, they are shared out evenly and the Review screen warns "Not enough contacts to meet all minimums".

**Example:** 100 contacts and 10 coordinators. Coordinators 1–9 have Min 3 and Max 10. Coordinator 10 has Min 3 and no Max.
- Minimums: 10 × 3 = 30 given, so 70 are left.
- Even share: everyone climbs together to 10, which uses 9 × 7 = 63 more for coordinators 1–9 and 7 for coordinator 10. That accounts for all 70.
- If there are 130 contacts instead, coordinators 1–9 stop at 10 and the remaining contacts all go to coordinator 10, who has no Max.
- If coordinator 10 also has Max 10, then 130 − 100 = **30 are left over**, and the Review screen says so.

Min and Max count only what this assignment gives, not calls from other events.

---

## 4. Flow B: Follow-up calls (5 steps)

1. **Event**
2. **Which calls?** Tick one or more statuses (Busy, No answer, Call back, …) and optionally a date range. A breakdown shows how many have each status.
3. **Narrow down** (optional): the same field filters and analytics as Flow A, Step 2.
4. **Coordinators**: either "Same coordinator as before" or tick coordinators and set Min/Max. The same sharing rule applies.
5. **Review → Save**

Follow-up calls are marked as follow-up and **never remove or replace** the normal assignment.

---

## 5. Flow C: Move a coordinator's calls (4 steps)

1. **Event**
2. **From whom?** Tick one or more coordinators. The screen shows only their **untouched** count, for example "Suresh: 37 untouched (21 already called, these stay)".
3. **To whom?** Tick coordinators and set Min/Max. An option, **"Also give new untouched contacts"**, adds contacts that are in nobody's list yet.
4. **Review → Save**

---

## 6. Backend changes (Cloudflare Worker, `backend/src/index.ts`)

| Endpoint | Purpose |
|---|---|
| `POST /admin/assign/breakdown` | Takes `{event, filters}` and returns `{total, fields: {college: [{id,title,count}], ..., empty counts}}`. Only counts, never names. It reads people once (≤5000, only the fields it needs) and counts in the Worker. |
| `POST /admin/assign/plan` | New body: `{kind, event, pool_filters, groups:[{filters, coordinators:[{mob,min,max}], keep_previous}], rest}`. It returns the per-coordinator counts, left over, replaced, and the moves. Nothing is written. |
| `POST /admin/assign/apply` | Unchanged (batches of 100, safe to repeat). |
| `POST /admin/assign/release` | New, run after the last batch in Flow A only. It deletes untouched, non-follow-up rows for the event that are not in the plan, in batches. |

Filter shape (the same everywhere): `{field, mode: "only" | "except", values: [ids, "" for Empty]}`.
Allowed fields are a fixed list on the server, so the app can't send arbitrary ERPNext fields. Skill and Interest are child tables,
so they are read from `FOLK User Skill` and `FOLK User Interest`.

`distribute()` is rewritten to follow the Min/Max rule above, and it gets unit tests that use the example from section 3.

## 7. App changes (Flutter)

- `lib/features/admin/assign/` gets one file per step and a single `AssignWizard` state (Riverpod notifier) that holds the whole plan.
- Reusable widgets: `FieldBreakdown` (bars with count, %, tick boxes and the only/except switch), `FilterChips` and `CoordinatorLimits` (Min/Max rows).
- All sizes and colours come from the existing theme tokens, as in `docs/STANDARDS.md`.
- The old `assign_screen.dart` is deleted once the wizard works.

---

## 8. Decisions to confirm before building

1. **"Previous contacts"**: read here as *all older contacts, including imported ones, can be assigned*, plus the *"Same coordinator as before"* switch. Is that correct?
2. **A contact in two groups goes to the first group.** Is that OK?
3. **Assigning again** replaces untouched calls for the **whole event**, not only for the coordinators in the new plan. Is that OK?
4. **Min/Max count only this assignment**, not the calls a coordinator already made. Is that OK?
