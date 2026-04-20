# Changelog

## 0.3.2 — 2026-04-20

Big consolidated release. Everything drafted through 0.4 / 0.5 / 0.6 / 0.7 is now shipped in one bundle — the in-between version numbers were never published.

### Invoice-from-PDF flow (expense + purchase invoice with PZ)

Claude reads a PDF or photo of an invoice from chat and posts the right record — no server-side OCR. The `/expenses/upload` and `/purchase-invoices/upload` endpoints remain for the web UI only.

- `workflows/create-from-invoice-pdf.md` — **unified flow** that classifies the document first (services → `/expenses`, goods-for-stock → `/purchase-invoices` with optional PZ), asks only when genuinely ambiguous (mixed lines, unmatched goods, fixed assets). Covers a Polish *faktura VAT* layout: *Sprzedawca*, *Razem netto / VAT / brutto*, per-line *Nazwa / Ilość / Cena jedn. / VAT % / Wartość netto / brutto*, plus *paragon* / proforma / corrective / non-PLN / duplicate edge cases.
- `reference/finance.md` — endpoints table, `CreateExpenseDto` + `ExpenseItemDto` field-by-field, VAT rates, rounding rule (`totalVat = totalGross - totalNet`, reconcile to invoice totals).
- `reference/purchases.md` — suppliers (create / search / GUS lookup), purchase invoices (`CreatePurchaseInvoiceDto`, `PurchaseInvoiceItemDto`), warehouses endpoint, PZ auto-create vs. manual (`POST /purchase-invoices/:id/create-pz`, `/cancel-pz`), product-matching strategy, common pitfalls (`supplierId` required unlike expenses; `autoCreatePZ` needs `warehouseId`; no free-form item description — every line hangs off a real product).
- `scripts/upload-receipt.sh` — multipart POST to `/expenses/receipt-upload`, returns `{ fileUrl }`. Shared between expense and purchase-invoice flows; the folder name is cosmetic.

### Product matching by Claude (not backend fuzzy search)

For the purchase-invoice branch, Claude matches invoice lines to catalog entries **in its own context** instead of delegating to `/products/search?q=<item-name>` per line. The backend's search AND-s every token through unaccent + ILIKE on `name / sku / barcode`, so an invoice line like `"Dorsz filet świeży 1 kg"` forces `świeży` **and** `1` **and** `kg` to all appear on the catalog entry — one extra qualifier the product name doesn't print → zero results, even when the product exists. Per-item search also meant N API calls for an N-line invoice.

New flow (`workflows/create-from-invoice-pdf.md` step 5B.1):
- One bulk `GET /products/search?q=&limit=2000` → flat `{id, name, sku, unit: {id, abbreviation}}[]`.
- Claude matches semantically (primary noun, size qualifier, form, unit, SKU if printed; diacritics ignored; 1kg ≠ 5kg).
- Table with confidence shown to the user for confirmation.
- Fallback for >2000 SKUs: filter by category first, or targeted 1–2-token search.

### Product management from chat

Create and update products, categories and units. **Delete is intentionally not supported** — it breaks historical orders, PZs and stock movements. The skill proposes `PUT {isActive: false}` for "hide" instead, and only falls back to real DELETE if the user explicitly acknowledges the consequences (and even then, redirects to the web UI).

- `reference/products.md` — endpoints table (products + categories + units), `CreateProductDto` + `UpdateProductDto` field-by-field, SKU auto-generation behaviour, category-tree vs. flat list guidance, matching rules for `categoryId` / `unitId`, no-delete rule at the top.
- `workflows/add-product.md` — collect name / category / unit / price → dedupe via `/products/search` → resolve `categoryId` from `/categories/tree` (ask before creating a new category) → resolve `unitId` from `/units` → preview → POST. Covers gross-instead-of-net mistakes, purchase-vs-sale-price confusion, SKU collisions, units not in the dictionary.
- `workflows/update-product.md` — find via search → map user phrasing (Polish / Russian / English vocab for price, VAT, min-stock, weight, barcode) to DTO fields → partial PUT with only the changing fields → confirm. Explicitly refuses destructive DELETE.

### UI "how do I…" guides for non-technical users

The skill now answers UI questions ("where do I click", "how do I upload the invoice", "how do I mark it paid"), not just programmatic API calls. Claude answers from `guides/` for end users and translates steps into their language.

- `guides/expenses.md` — full walkthrough of the Expenses module: menu location, OCR invoice upload, manual entry, line items, marking paid / reverting, bank-accounts tab, categories, filters, FAQ. Based on the current `apps/web` UI (dialogs, fields, button labels) — kept in English; Claude translates at answer time.

### SKILL.md

- Description expanded: classifier + PZ, product add/edit with no-delete note, end-user UI questions.
- Map gains `guides/` (top), fills in `reference/purchases.md`, `reference/products.md`, `reference/finance.md`, and adds workflow entries for invoice-PDF, add-product, update-product.
- `upload-receipt.sh` listed in scripts — shared between expense and purchase flows.

### Backend (companion commits)

- `POST /api/v1/expenses/receipt-upload` — upload-only, no OCR, returns `{ fileUrl }`. Same file types / size cap as `/expenses/upload`. The existing `/expenses/upload` stays for the web UI.
- `GET /products/search` now accepts `?limit=N` (default 20, capped at 2000). `?q=&limit=2000` dumps the full active catalog alphabetically as a flat `{id, name, sku, unit: {id, abbreviation}}[]` — intended as the one-shot bulk-fetch for Claude's in-context matching. Existing callers (`limit` omitted) keep the 20-row default, so the Telegram purchase-invoice handler and web UI selectors are unaffected.

## 0.3.1 — 2026-04-16

Marketplace repo moved from GitLab to GitHub:
`https://github.com/EduardKarnaukh/freshfork-claude-skill.git`

Existing users need to re-add the marketplace with the new URL. Docs and
SKILL.md updated.

## 0.3.0 — 2026-04-16

Non-technical users shouldn't have to open a terminal. Claude now drives `login.sh` itself.

Skill changes:
- `SKILL.md` setup section rewritten: Claude should *run* `login.sh` when the config is missing, not tell the user to copy-paste a shell command. It also captures the Approve URL from the script's stdout and posts it back to chat as a clickable link (fallback in environments where auto-`open` doesn't reach the user's browser).
- Same section documents the fallback path if `login.sh` can't open a browser (rare) and the re-auth path when PATs expire.

Related UI polish (separate change in `apps/web`):
- `/settings/connect-cli` page is now copy-oriented for end users rather than developers — bigger CTA, drops IP/user-agent/request-code rows, reworded title and success message.

## 0.2.0 — 2026-04-16

**Company lookup moved server-side.** The skill no longer calls the MinFin Whitelist API directly; instead it uses the CRM's new `POST /integrations/gus/lookup` endpoint, which proxies the Polish GUS BIR1 registry and returns a pre-parsed record (companyName, nip, regon, krs, street, postalCode, city, email, phone).

Why this matters:
- **More data.** GUS BIR1 returns KRS, REGON and correctly split street/postalCode/city — no regex gymnastics in the skill.
- **One auth surface.** The skill now only talks to the CRM API using the user's PAT. No external HTTP from the Bash side.
- **Cowork-ready.** A future MCP server can expose this lookup as a tool to Cowork users without any shell-script dependency.

Skill changes:
- `workflows/add-client-by-nip.md` — step 2 now calls `POST /integrations/gus/lookup`; address parsing removed (server returns parsed fields).
- `reference/clients.md` — added a **Company lookup (GUS)** section with request/response shapes and error handling.
- `scripts/pl-company-lookup.sh` — **removed** (CRM handles the lookup now).
- `SKILL.md` — scripts list updated; added a pointer to the GUS endpoint.

Backend changes (shipped previously, documented here):
- `apps/api/src/modules/integrations/gus/` — client, service, controller, DTOs.
- `POST /api/v1/integrations/gus/lookup` with permission `clients.create`.
- Configured via `GUS_API_KEY` env var — apply for a key at https://api.stat.gov.pl/Home/RegonApi. Without it the endpoint responds 503.

Distribution:
- Plugin marketplace moved to a dedicated public GitHub repo: https://github.com/EduardKarnaukh/freshfork-claude-skill
- Users install via `/plugin marketplace add https://github.com/EduardKarnaukh/freshfork-claude-skill.git` then `/plugin install freshfork-crm@freshfork`.

## 0.1.0 — 2026-04-16

Initial scaffold, packaged as a **Claude plugin** (works in both Claude Code CLI and Cowork).

- Plugin layout: `.claude-plugin/plugin.json` at the root, skill under `skills/freshfork-crm/`
- `skills/freshfork-crm/SKILL.md` — map, auth rules, general conventions
- `skills/freshfork-crm/reference/clients.md` — clients module
- `skills/freshfork-crm/workflows/add-client-by-nip.md` — create a client from a Polish NIP using the Ministry of Finance Whitelist API
- `skills/freshfork-crm/scripts/api.sh` — curl wrapper with Bearer auth and `/api/v1` prefix
- `skills/freshfork-crm/scripts/login.sh` — device-code login flow (opens browser, user approves on `/settings/connect-cli`, script saves PAT to `~/.freshfork/config`)
- `skills/freshfork-crm/scripts/pl-company-lookup.sh` — look up a Polish company by NIP via MinFin Whitelist (removed in 0.2.0)

Backend that shipped alongside:
- `ApiToken` + `CliAuthRequest` Prisma models
- `api-tokens` module (`POST`/`GET`/`DELETE /api-tokens`)
- PAT validation wired into the global `JwtAuthGuard`
- Device-code endpoints: `POST /auth/cli/start`, `GET /auth/cli/status`, `GET /auth/cli/describe`, `POST /auth/cli/approve`

Frontend (`apps/web`):
- `/settings/connect-cli` approval page with `settings.connectCli.*` translations in `ru.json` and `en.json`

TODO:
- admin page `/settings/api-tokens` (list, create, revoke) for non-CLI use
- MCP server for Cowork (skill relies on local Bash, which Cowork doesn't have)
- reference files for remaining modules: orders, products, warehouse, purchases, sales, finance, reports, tasks, integrations
- more workflow files: create-order, stocktake, OCR-invoice
