# Purchases: suppliers, purchase invoices, PZ

The purchases module tracks **supplier invoices for goods that enter the warehouse**. Each purchase invoice can spawn a `PZ` (*przyjęcie zewnętrzne* — "goods receipt") document that increases stock on a specific warehouse. Contrast with `reference/finance.md`: expenses are for operational costs that never touch stock (rent, utilities, services).

**Border rule:** affects stock? → Purchase invoice. Doesn't? → Expense.

An invoice with `items[]` that references real `productId`s will either auto-create a confirmed PZ at creation time (`autoCreatePZ: true`) or let you create it later via `POST /purchase-invoices/:id/create-pz`. An invoice without `items[]` is legal — it's just a financial record without a stock movement.

## Endpoints

### Suppliers

| Method | Path                              | Purpose                                             |
| ------ | --------------------------------- | --------------------------------------------------- |
| GET    | `/suppliers`                      | Paginated list (filter by `search`, `isActive`)    |
| GET    | `/suppliers/search?q=<nip\|name>` | Flat array for selectors. Empty array if no match  |
| GET    | `/suppliers/:id`                  | Get by UUID                                         |
| POST   | `/suppliers`                      | Create                                              |
| POST   | `/suppliers/gus-lookup`           | Look up a Polish company by NIP/REGON/KRS (proxies `/integrations/gus/lookup`) |
| PUT    | `/suppliers/:id`                  | Update                                              |
| DELETE | `/suppliers/:id`                  | Soft delete                                         |

### Purchase invoices

| Method | Path                                       | Purpose                                                     |
| ------ | ------------------------------------------ | ----------------------------------------------------------- |
| GET    | `/purchase-invoices`                       | Paginated list (filters: `status`, `supplierId`, `dateFrom/To`, `search`) |
| GET    | `/purchase-invoices/:id`                   | Get invoice with items (each item has resolved `product`)   |
| POST   | `/purchase-invoices`                       | Create invoice — optionally `autoCreatePZ: true` with `warehouseId` |
| POST   | `/purchase-invoices/upload`                | Upload + run server-side OCR (web UI). Returns `{fileUrl, ocrData, supplier, matchedItems}`. **Don't use from the skill** — you parse the PDF yourself |
| PUT    | `/purchase-invoices/:id`                   | Update (items array fully replaces existing)                |
| DELETE | `/purchase-invoices/:id`                   | Cancel (soft delete). Fails if a confirmed PZ is attached — cancel the PZ first |
| POST   | `/purchase-invoices/:id/create-pz`         | Create PZ for an existing invoice. Body: `{warehouseId: UUID}` |
| POST   | `/purchase-invoices/:id/cancel-pz`         | Cancel the attached PZ (reverses stock movements)           |

### Warehouses (for PZ)

| Method | Path                    | Purpose                                          |
| ------ | ----------------------- | ------------------------------------------------ |
| GET    | `/warehouses/active`    | Flat list of active warehouses for selectors. Use this when picking a target warehouse for a PZ |
| GET    | `/warehouses`           | Paginated list with full data                    |
| GET    | `/warehouses/:id`       | Get by UUID                                      |

### File upload

There is no `/purchase-invoices/receipt-upload` — when *you* parsed the PDF, reuse the expenses upload endpoint:

```bash
bash "$SKILL_DIR/scripts/upload-receipt.sh" /path/to/invoice.pdf
```

That hits `/expenses/receipt-upload` and returns `{ fileUrl }`. The URL contains `expenses/` in the path — that's fine, it's just a storage folder; the purchase invoice references the URL via `fileUrl`, not the folder.

Full schemas in Swagger, tags `Suppliers`, `Purchase Invoices`, `Warehouses`.

## Key fields — CreateSupplierDto

**Required:**
- `companyName: string`

**Optional:**
- `nip: string` — 10 digits, no dashes. Unique — creating a second supplier with the same NIP fails
- `contactPerson: string`
- `email: string`
- `phone: string`
- `paymentTermDays: int` — net payment days (e.g. `14`, `30`)
- `bankAccount: string` — IBAN string (stored as typed)
- `notes: string`

For company lookup (NIP → companyName + address + REGON + KRS), use `POST /suppliers/gus-lookup` with `{nip: "..."}`. Returns a normalized `GusCompanyDto` — merge those fields into `CreateSupplierDto` before POSTing to `/suppliers`.

## Key fields — CreatePurchaseInvoiceDto

**Required:**
- `invoiceNumber: string` — copy from the PDF verbatim (e.g. `"FV/2026/001"`)
- `supplierId: UUID` — must match an existing supplier (unlike expense, this is **not optional**)
- `invoiceDate: string` — ISO date (invoice issue date, not today)

**Optional:**
- `dueDate: string` — ISO date
- `totalNet, totalVat, totalGross: number` — recomputed from `items[]` if items are present
- `currency: string` — default `"PLN"`
- `fileUrl: string` — URL from `upload-receipt.sh`
- `warehouseId: UUID` — required when `autoCreatePZ: true`
- `autoCreatePZ: boolean` — default `false`. When `true` + items present + warehouseId set → API creates a confirmed PZ in the same transaction
- `notes: string`
- `items: PurchaseInvoiceItemDto[]` — at least 1 element if you pass `items` at all (`@ArrayMinSize(1)`)
- `type: 'INVOICE' | 'RECEIPT'` — invoice (*faktura VAT*) vs receipt (*paragon*). Default `INVOICE`
- `ocrData: object` — the OCR blob (from `/purchase-invoices/upload`). Not for us — we parsed ourselves

**PurchaseInvoiceItemDto:**

| Field        | Type   | Required | Notes                                              |
| ------------ | ------ | -------- | -------------------------------------------------- |
| `productId`  | UUID   | yes      | Must match a real product. See "Matching line items" below |
| `quantity`   | number | yes      | At least `0.001`. Decimals OK (e.g. `2.5` kg)      |
| `unitPrice`  | number | yes      | Net unit price                                     |
| `vatRate`    | number | no       | Percent: `0`, `5`, `8`, `23`. Default `23`         |

Unlike `ExpenseItemDto`, **there is no free-form `description`** — every line must hang off a real product. If the PDF has an item we can't match, the options are: create a new product first, pick a similar existing product, or skip the item (and the invoice will be financially-only, no PZ).

## Matching line items to products

Each invoice line needs a `productId`. **You** do the match — don't lean on the backend's per-item fuzzy search.

**Why not `/products/search?q=<item-name>`?** It AND-s every token through unaccent + ILIKE on `name / sku / barcode`, so a full line like `"Dorsz filet świeży 1 kg"` forces `świeży` AND `1` AND `kg` to all appear somewhere on the catalog entry. Any extra qualifier the invoice prints but the product name doesn't → zero results, even though the product exists.

**Preferred: dump the active catalog once, match in your own context.**

```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/products/search?q=&limit=2000"
```

Returns a flat `[{id, name, sku, unit: {id, abbreviation}}, ...]`. `limit` is capped at 2000 server-side; `q=""` disables the token filter so you get the full active catalog alphabetically.

Now match in context. Signal to weigh:

- **Primary noun** (`dorsz`, `łosoś`, `mąka`) — what the product IS
- **Size qualifier** (`1kg` vs `5kg` — keep distinct, these are different SKUs)
- **Form** (`świeży` / `mrożony`, `filet` / `dzwonki`)
- **Unit** — invoice `j.m.` column (kg, szt., l, opak.) should line up with catalog `unit.abbreviation`
- **SKU printed on the invoice** (if any) — always trumps name matching
- **Diacritics** — ignore (`Żurawina` == `Zurawina`)

Outcome per line:

- **Matched with confidence** → use the catalog entry's `id` as `productId`
- **Ambiguous** → show the user 2–3 top candidates (name + sku + unit), let them pick
- **No match** → ask: "Line '<name>' isn't in the catalog. Create a new product, pick an existing one manually, or skip this line?"
  - Creating goes through the `add-product` workflow (`POST /products` — needs name, categoryId, unitId)
  - Skipping omits the line from `items[]` — financial record stays, but the line won't land on the PZ and its stock won't increase

**Fallback: per-item search for huge catalogs.** If the user has >2000 active SKUs, filter by category first (`GET /categories/tree` → pick → `GET /products?categoryId=<uuid>&isActive=true&perPage=100` paginated), or fall back to `/products/search?q=<keyword>` with 1–2 **distinctive** tokens (extract the primary noun; drop units, adjectives, and pure digits before querying).

## PZ — auto-create vs. manual

Two ways to create the PZ:

### A) Auto at invoice creation (preferred when it's clear where stock goes)

```jsonc
POST /purchase-invoices
{
  "invoiceNumber": "...",
  "supplierId": "...",
  "invoiceDate": "...",
  "items": [ { "productId": "...", "quantity": ..., "unitPrice": ... } ],
  "warehouseId": "<uuid>",
  "autoCreatePZ": true
}
```

The API creates the invoice, then creates a PZ (status `CONFIRMED`) linked to it, and applies stock movements. Atomic — either both succeed or neither.

### B) Manual after the fact

```jsonc
POST /purchase-invoices                      // no warehouseId, autoCreatePZ=false (default)
POST /purchase-invoices/<id>/create-pz       // later
{ "warehouseId": "<uuid>" }
```

Useful when the warehouse isn't known yet (e.g. goods haven't arrived, distributing across multiple locations).

**Cancel a PZ:** `POST /purchase-invoices/<id>/cancel-pz` — reverses the stock movements. The invoice stays. You can then re-issue a PZ to a different warehouse.

## Status model

Purchase invoices:
- `PENDING` — invoice recorded, awaiting payment
- `PAID` — via payment flow (outside this reference)
- `CANCELLED` — soft-deleted

PZ (warehouse document):
- `DRAFT` → `CONFIRMED` (triggers stock movement) → `CANCELLED` (reverses it)
- When created via `autoCreatePZ: true`, the PZ is `CONFIRMED` immediately

## Common pitfalls

- **`supplierId` is required** — unlike expenses, a purchase invoice can't exist without a supplier. If you couldn't read the NIP or match an existing supplier, resolve the supplier first (create via GUS lookup if needed), then POST the invoice.
- **Duplicate NIP** — `POST /suppliers` with an existing `nip` returns 409. Always search first: `/suppliers/search?q=<nip>`.
- **`items` with no matchable products** — don't silently fabricate a `productId`. Either match, create-then-match, or omit the line.
- **`autoCreatePZ` without `warehouseId`** — the API rejects this. Either set both or neither.
- **Polish NIPs** — 10 digits. Strip dashes/spaces. Some PDFs print `PL1234567890` — strip the country prefix too.
- **Receipt (*paragon*) vs. invoice** — a paragon has no NIP of the buyer and usually no itemized VAT. If the PDF is clearly a paragon, pass `type: "RECEIPT"`. It still goes through the same endpoint.
- **Corrective invoice (*faktura korygująca*)** — amends a prior invoice. Out of scope for the "from PDF" flow — ask the user which invoice to amend, then `PUT /purchase-invoices/:id` with the corrected items. A PZ needs to be cancelled and re-issued if quantities change.
