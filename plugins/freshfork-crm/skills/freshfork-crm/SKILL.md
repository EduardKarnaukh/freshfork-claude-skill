---
name: freshfork-crm
description: Freshfork CRM — a Polish B2B CRM. Use this skill whenever the user asks to do anything in Freshfork — add/find a client, add or edit a product, create an order, check stock, look at sales, manage tasks, purchases, expenses, or integrations (Fakturownia, Allegro, Telegram). Also covers end-user "how do I…" questions about the UI (where to click, what to upload) via `guides/` — answer from there for non-technical users instead of the API reference. Includes a unified flow for posting an invoice from a PDF/photo that classifies it as either an operational expense (phone, internet, rent, services) or a purchase invoice for goods that hit stock (auto-creates a PZ receipt document). Products can be created and updated but never deleted — use `isActive: false` to hide. Polish B2B context — NIP/REGON, Polish companies, PLN.
---

# Freshfork CRM skill

CRM for Polish B2B (franchisee product sales). This skill is a map of the REST API and business workflows. Detailed field schemas live in Swagger — do not duplicate them here.

## How to invoke the shell scripts

Scripts live in `scripts/` next to this `SKILL.md`. Inside a running Claude session the plugin install path is exposed as `${CLAUDE_PLUGIN_ROOT}`:

```bash
# skills directory when installed as a Claude plugin (CLI + Cowork):
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/freshfork-crm"
```

All examples below use `$SKILL_DIR` as shorthand for that path. If for some reason `$CLAUDE_PLUGIN_ROOT` is unset (e.g. you're reading this file via a raw path during development), derive `SKILL_DIR` from the absolute path of this `SKILL.md` — the Read tool showed it to you.

## Before you start

1. Check that the config exists: `~/.freshfork/config` must contain `FRESHFORK_URL` and `FRESHFORK_TOKEN`. If it doesn't — see the Setup section below.
2. Use `$SKILL_DIR/scripts/api.sh` for every API call:
   ```bash
   bash "$SKILL_DIR/scripts/api.sh" GET /clients?perPage=5
   bash "$SKILL_DIR/scripts/api.sh" POST /clients -d '{"companyName":"..."}'
   ```
   The script reads the config, adds the Bearer header and `/api/v1` prefix, and returns JSON.
3. The full schema for any endpoint is in Swagger: `${FRESHFORK_URL}/api/docs` (JSON at `${FRESHFORK_URL}/api/docs-json`). If the reference files here are not enough — look at Swagger.

## Map

### guides/ — end-user "how do I…" UI walkthroughs
When the user is asking about the *UI* ("where do I click", "how do I upload the invoice", "how do I mark it paid") — they are a non-technical CRM user, not a developer. Answer from `guides/`, **not** from `reference/`. Translate steps into the user's language; keep button labels verbatim if helpful.

- [`guides/expenses.md`](guides/expenses.md) — full UI walkthrough for the Expenses module: where it is, OCR upload flow, manual entry, line items, marking paid, bank accounts, filters, FAQ

### reference/ — per-module references
- [`reference/clients.md`](reference/clients.md) — clients, contacts, addresses, groups, search by NIP
- `reference/orders.md` — *(TODO)* orders, statuses DRAFT→CONFIRMED→…→INVOICED, comments
- [`reference/products.md`](reference/products.md) — products, categories (tree), units of measure. **No-delete rule**: use `PUT {isActive:false}` to hide, never `DELETE`
- `reference/warehouse.md` — *(TODO)* warehouses, receipt/issue documents, stock movements, production
- [`reference/purchases.md`](reference/purchases.md) — suppliers, purchase invoices, PZ (warehouse receipt), auto-create PZ flow, product matching
- `reference/sales.md` — *(TODO)* leads, deals, activities, pipeline stages
- [`reference/finance.md`](reference/finance.md) — expenses, line items, categories, bank accounts, upload + OCR
- `reference/reports.md` — *(TODO)* sales report and filters
- `reference/tasks.md` — *(TODO)* tasks, statuses, kanban
- `reference/integrations.md` — *(TODO)* Fakturownia (invoicing), Allegro, Telegram, OpenAI OCR

### workflows/ — business scenarios
- [`workflows/add-client-by-nip.md`](workflows/add-client-by-nip.md) — create a client from a Polish NIP using the Ministry of Finance Whitelist API
- [`workflows/create-from-invoice-pdf.md`](workflows/create-from-invoice-pdf.md) — user drops a PDF/photo of an invoice → *you* parse it (Read tool) → **classify as expense vs. purchase invoice** (ask if unclear) → match supplier → (expense) pick category; (purchase) match products to catalog, optionally auto-create PZ → attach file → POST to `/expenses` or `/purchase-invoices`
- [`workflows/add-product.md`](workflows/add-product.md) — collect name + category (from `/categories/tree`) + unit (from `/units`) + optional price/VAT/min-stock → preview → POST `/products`. SKU auto-generated if not given. Checks for duplicates first
- [`workflows/update-product.md`](workflows/update-product.md) — find by name/SKU → partial `PUT` with only the changing fields. Hide via `isActive: false`; **never `DELETE`** (breaks historical orders/PZs/stock)

### scripts/ — shell wrappers
- `scripts/api.sh` — curl + Bearer + `/api/v1` prefix (JSON endpoints)
- `scripts/upload-receipt.sh` — multipart POST to `/expenses/receipt-upload` (attach a PDF/image to an expense *or* purchase invoice — no OCR; the backend stores the file and returns a URL)
- `scripts/login.sh` — device-code auth flow (opens browser, saves PAT to config)

For company lookup by NIP/REGON/KRS use the CRM endpoint `POST /integrations/gus/lookup` — it proxies the Polish GUS BIR1 registry and normalizes the response. No external API calls from the skill side.

## General rules

**Auth**: JWT bearer token. If the API returns `401` the token is expired or invalid. Tell the user to re-run `login.sh`. Do not try to "fix" it on your own.

**URL prefix**: every endpoint lives under `/api/v1`. `api.sh` adds it for you — pass the path without the prefix.

**Identifiers**: UUID v4 everywhere. If you need an ID, look it up first via `GET` + search (`?search=...` or a dedicated `/search` endpoint). Do not invent IDs.

**Pagination**: default `perPage=20`, maximum depends on the module. Params: `page` (1-based), `perPage`, `search` — check the reference file for the specific module.

**Dates**: ISO 8601 with a timezone offset, e.g. `2026-04-16T12:00:00+02:00`. Always include the offset.

**Money / numbers**: `unitPrice`, `creditLimit`, etc. are numbers (not strings), in the base currency (PLN). VAT is a percentage (0, 5, 8, 23).

**Localization**: the API speaks English. UI strings are translated in `apps/web/messages` — you don't need to touch those.

**Idempotency**: POST is not idempotent. Before creating something (especially clients and suppliers), check that it doesn't exist yet (`/clients/search?q=<NIP>`). Otherwise you'll create duplicates.

**Cancel / delete**: DELETE is almost always a soft delete (sets `isActive=false` or `deletedAt`). Hard deletes go through the DBA — don't attempt them.

## Confirmations before writes

Before any mutating operation (POST/PUT/DELETE/PATCH), **always** show the user:
- what you are about to do (method + path)
- the request body
- a short summary in the user's language

Then wait for confirmation. Exception: when the user has explicitly said "go ahead, don't ask" in the current session.

## Setup (first run)

If `~/.freshfork/config` doesn't exist, handle it yourself — do not tell the user to open a terminal and run commands. Users aren't developers.

### Preferred flow (run it yourself)

1. Tell the user briefly: "I need to connect to Freshfork on your behalf. I'll open an approval page in your browser — please click **Approve** when it loads."
2. Run the login script. Pass the default URL so no interactive prompt blocks:
   ```bash
   bash "$SKILL_DIR/scripts/login.sh" https://crm.similar.group
   ```
3. The script prints a line like `Approve URL: https://crm.similar.group/settings/connect-cli?code=ABCD-EFGH`. **Copy that URL verbatim and put it in your chat reply as a clickable link**, so the user sees it even if auto-open didn't work in their environment.
4. The script opens the URL in the user's default browser (macOS `open` / Linux `xdg-open`). The user clicks Approve on the page.
5. The script polls `/auth/cli/status` internally and, once approved, writes `~/.freshfork/config` (chmod 600). The PAT is valid for 90 days.
6. Once the script exits with success, continue with whatever the user originally asked.

### If `login.sh` fails or times out

Fallback (rare — only when the sandbox has no `open`/`xdg-open` AND the user can't click the URL): show them the Approve URL from step 3 and say "open it, click Approve, then tell me when you're done". After they confirm, re-run `login.sh` (it will read the now-existing approved request from the same `code`) OR poll `/auth/cli/status` directly.

### If auth is broken later

If API calls return `401` / "Invalid or expired API token" — the PAT was revoked or expired. Tell the user "I need to reconnect" and run `login.sh` again (it will replace `~/.freshfork/config`).

## Updating the skill

This skill is shipped as a Claude plugin. Plugins auto-check for updates from the Freshfork marketplace at every session start.

**Marketplace URL**: `https://github.com/EduardKarnaukh/freshfork-claude-skill.git`

To update manually:
- Claude Code CLI: `/plugin marketplace update freshfork`
- Cowork: Settings → Plugins → click the update icon next to `freshfork-crm`

Release history: see `CHANGELOG.md` at the plugin root.

---

**Plugin version**: see `.claude-plugin/plugin.json`.
