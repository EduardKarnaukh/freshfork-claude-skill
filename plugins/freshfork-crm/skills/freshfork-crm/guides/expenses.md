# Expenses — UI guide

Step-by-step guide for **end users** of the CRM: where to click, what to upload. When the user asks "how do I add an expense", "where do I upload the invoice", "how do I mark it paid" — answer from this file, **not** from `reference/finance.md`.

Reply in the user's language (the UI is localized to RU/PL/EN — translate steps, keep button labels verbatim if helpful).

For programmatic tasks (REST API), use `reference/finance.md` instead.

## Where it lives

Left sidebar → **Expenses** (RU: «Расходы», PL: «Wydatki»). Opens on the "Expenses" tab. There's a second tab, "Bank accounts", where bank accounts and cashboxes are maintained (used later when marking payments).

## What this module is for

Tracks **operational / overhead costs**: rent, utilities, hosting, transport, marketing, services, office supplies. Everything that **doesn't hit the warehouse**. Goods purchases (that increase stock) are handled in a separate module, **Purchases** — don't put rent there, don't put a batch of goods here.

Simple rule: **affects stock → Purchases. Doesn't → Expenses.**

## Main screen (Expenses tab)

Top row — search and filters:
- **Search** — by invoice number, description, supplier
- **Status** — All / Unpaid / Paid
- **Category** — when set, only expenses in that category are shown

Top right — the **Create expense** button (with a plus icon).

Below the filters is the expenses table. Columns: date, invoice number, category, supplier, description, amount, status, and action icons (pencil — edit, checkmark — mark as paid, cross — mark as unpaid).

## How to create an expense from a scan/PDF (the fast path)

The OCR-based flow — the system reads the invoice and pre-fills the form.

1. Click **Create expense** (top right).
2. The dialog opens. At the top — a large drop zone "Drag & drop your receipt or invoice". Either drag a file in, or click to open a file picker.
   - Accepted: JPG, PNG, WEBP, PDF. Max **10 MB**.
3. Wait a few seconds — OCR is processing. Progress is shown in the same zone ("Processing OCR…").
4. When done, a green check appears with an **Apply to form** button. Above it — a preview of what was extracted (invoice number, supplier with NIP, total gross, item count). On the right — the OCR confidence %.
5. Click **Apply to form** — the fields below will auto-fill: date, invoice number, due date, description, line items with all totals and VAT, the grand total.
6. Review and fix as needed. In particular, **category is not filled by OCR** — pick it from the list:
   - **Category** — required. Pick from the list (rent, hosting, etc. — the list is pre-populated).
   - **Supplier** — not filled by OCR. Pick from the supplier search (searches by name or NIP). If the supplier doesn't exist yet, you have to create them in **Purchases → Suppliers** first.
7. Click **Create expense** at the bottom. The expense appears in the table with status "Unpaid".

### When OCR doesn't parse well

- Check the confidence % on the preview. Below 70% → something is off.
- You can skip **Apply to form** and fill everything manually by looking at the file. The scan is still attached to the expense either way.
- Category is always chosen by hand — OCR doesn't know it.
- Non-standard VAT rates (0%, 5%, 8% — not the usual 23%) are usually picked up correctly, but double-check the line items.

## How to create an expense manually (no scan)

Sometimes there's no file (cash payment, utility bill in a web cabinet, a receipt you don't have a scan of):

1. Click **Create expense**.
2. **Skip the upload zone** — just don't touch it.
3. Fill the fields:
   - **Category** (required)
   - **Date** (required — defaults to today; use the invoice date)
   - **Supplier** (optional)
   - **Invoice number** (if any)
   - **Amount (gross)** — the total with VAT
   - **Total net** and **VAT** — optional (when you record a flat sum without line items)
   - **Due date** — if there's a payment deadline
   - **Description** — a short note about what this expense is
4. Click **Create expense**.

## Line items

Line items are for invoices with **multiple lines** having different amounts or different VAT rates (e.g. one invoice has both a 23%-VAT service and something at 8%).

Inside the create dialog there's a **Line items** section. Click **Add item** — a row appears with:
- **Description** — what the line is for
- **Qty** — decimals OK, e.g. `2.5`
- **Unit price** — per unit, net
- **VAT %** — 23, 8, 5, 0 (Polish rates). Defaults to 23%.
- **Net** / **VAT** / **Gross** — auto-computed from Qty × Price and the VAT rate. Net or Gross can be overridden manually; the other two recompute.

**Important:** once line items exist, the grand totals (Net / VAT / Amount) are **locked** and computed automatically as sums across items. That's by design.

Remove a line — trash icon on the right.

When there are no line items, fill the grand Net / VAT / Amount manually.

## Marking as paid

Once paid, record it so the expense doesn't stay "Unpaid" forever.

1. Find the expense in the table, click the **checkmark** icon in the actions column.
2. A small "Mark as paid" dialog opens. Fill:
   - **Payment method**: Bank transfer / Cash / Card
   - **Bank account** — where the money came from (account or cashbox — pick from the list). Can be left empty, but better to pick one.
   - **Payment date** — defaults to today.
3. Click **Mark as paid**. The table status flips to "Paid".

### Reverting a mark

Click the **cross** icon in the actions column (on a paid expense) — the status reverts to "Unpaid".

## Editing and deletion

- **Edit** — pencil icon in the row. The same dialog opens, pre-filled.
  - The upload zone is **hidden in edit mode** — you can't swap the attached file through the UI. The file uploaded at creation stays with the expense.
  - **Supplier can't be changed** in edit mode. If you picked the wrong one, delete the expense and create it again.
- **Delete** — not exposed in the table UI. Use the API or ask a developer if you really need to remove a record.

## Bank accounts tab

This is where bank accounts and cashboxes are managed. They're referenced when marking payments.

Fields when creating:
- **Account name** — display name (e.g. "mBank główne")
- **Bank name**
- **Account number**
- **Currency** (defaults to PLN)
- **Default** — will be pre-selected in dialogs
- **Cash (cashbox)** — check this for a physical cash box rather than a bank account
- **Active** — uncheck to hide from pickers

Mark-as-paid still works without any accounts — the payment just won't be linked to one.

## Expense categories

A catalog of categories (rent, hosting, transport, marketing, …). Each category can have a **monthly budget**, used in reports to flag overruns.

Categories can be hierarchical (parent + children). If there's no "Categories" tab visible in the UI, admins manage the catalog from a separate screen — ask an admin.

## Filters are remembered

Changing filters doesn't reload the page, and the filter state is **persisted in the browser** — next time you open the page, the same filters are applied. To clear, switch to "All statuses" / "All categories".

## FAQ

**"Can I just upload an invoice without filling a form?"** — No. Upload happens inside the Create-expense dialog; there's no standalone file storage.

**"I uploaded the wrong file."** — While the dialog is still open (expense not saved yet), just drag another file into the same zone — it replaces the previous one.

**"The supplier isn't in the list."** — Go to **Purchases → Suppliers** and add them there (NIP can be auto-filled via GUS lookup). Then return to the expense.

**"Invoice is in EUR but I'm entering in PLN — what do I do?"** — Change the **Currency** field in the expense (next to the amount — defaults to `PLN`, enter `EUR`, `USD`, etc. — three letters). Enter the amount in the invoice's currency. Reports handle conversion.

**"Can I duplicate a past expense?"** — Not yet. For recurring ones (subscriptions), create from scratch.

**"How do I see only unpaid ones?"** — Set the **Status** filter to "Unpaid".

**"Who created this expense?"** — Not shown in the edit dialog. The field (`createdBy`) exists in the API; ask a developer if you need to see it in the UI.
