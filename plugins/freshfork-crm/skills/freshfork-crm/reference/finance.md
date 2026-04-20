# Finance: expenses, categories, bank accounts

The expenses module tracks **operational / overhead costs** — things that do not end up in warehouse stock (rent, utilities, hosting, transport, marketing, services, office supplies). Contrast with `reference/purchases.md`: purchases are supplier invoices for goods that *do* hit the warehouse (`PurchaseInvoice` → auto-PZ document).

**Border rule:** affects stock? → Purchase. Doesn't? → Expense.

An expense has optional line items (`items[]`) capturing *what the invoice is for*. If the PDF has line items, store them — we derive totals from items when they're present.

## Endpoints

| Method | Path                               | Purpose                                               |
| ------ | ---------------------------------- | ----------------------------------------------------- |
| GET    | `/expenses`                        | Paginated list with filters (status, categoryId, supplierId, dateFrom/To, search) |
| GET    | `/expenses/:id`                    | Get expense by UUID (includes `items[]`)              |
| POST   | `/expenses`                        | Create expense (optionally with items)                |
| POST   | `/expenses/receipt-upload`         | **Upload file only (no OCR)** — returns `{fileUrl}`. Use this when *you* parsed the document yourself |
| POST   | `/expenses/upload`                 | Upload + run server-side OCR — returns `{fileUrl, ocrData}`. Used by the web UI |
| PUT    | `/expenses/:id`                    | Update expense (items passed in body fully replace existing ones) |
| PATCH  | `/expenses/:id/mark-paid`          | Mark as PAID (body: `{paymentDate?, paymentMethod?, bankAccountId?}`) |
| PATCH  | `/expenses/:id/mark-unpaid`        | Revert to UNPAID                                      |
| DELETE | `/expenses/:id`                    | Hard delete                                           |
| GET    | `/expense-categories`              | List categories (hierarchical, with monthly budget)   |
| POST   | `/expense-categories`              | Create category                                       |
| PUT    | `/expense-categories/:id`          | Update category                                       |
| GET    | `/bank-accounts`                   | List bank accounts (with `isCash` flag for cashboxes) |

For **supplier lookup** (matching a supplier name / NIP to an existing `Supplier`), use `/suppliers/search?q=<name-or-nip>` — it returns an array, empty if no match. See `reference/purchases.md` for supplier create/update.

Full schemas in Swagger, tag `Expenses`.

## File upload

Two endpoints — **pick the right one for your flow**:

### `POST /expenses/receipt-upload` — attachment only (use this one)

When you've parsed the document yourself (Claude reading a PDF/photo), use this endpoint. The server just stores the file in MinIO and returns a URL.

```bash
bash "$SKILL_DIR/scripts/upload-receipt.sh" /path/to/invoice.pdf
```

- **Content type:** multipart/form-data, field `file`
- **Accepted:** `image/jpeg`, `image/png`, `image/webp`, `application/pdf`
- **Max size:** 10 MB
- **Response:** `{ "fileUrl": "https://minio.../expenses/2026/04/<uuid>-invoice.pdf" }`

Use that `fileUrl` as `receiptUrl` on the expense body.

### `POST /expenses/upload` — OCR path (web UI only)

The web UI uses this: the server runs OpenAI OCR on the file and returns a parsed invoice structure. Costs an OCR call per upload. **Don't use this from the skill** — you're a better parser than this endpoint.

- Same file constraints as above
- Returns `{ fileUrl, ocrData }` where `ocrData` matches `OcrInvoiceResult` in `packages/shared/src/types/expense.types.ts`

## Key fields — CreateExpenseDto

**Required:**
- `categoryId: UUID` — must exist in `/expense-categories`
- `amount: number` — **gross** total in the base currency. Not VAT percentage — the actual PLN value with VAT.
- `date: string` — ISO date, e.g. `"2026-04-17"`. The invoice date, not payment date.

**Optional:**
- `currency: string` — default `"PLN"`; 3-letter ISO code
- `description: string` — free-form memo (what the expense is about, in plain language)
- `invoiceNumber: string` — e.g. `"FV/2026/001"`. Store what the PDF shows, verbatim
- `supplierId: UUID` — leave out if you couldn't match one. Do **not** invent
- `dueDate: string` — ISO date (payment deadline on the invoice)
- `totalNet: number` — net sum (before VAT). Recomputed from `items[]` if items are present
- `totalVat: number` — VAT sum. Same as above
- `receiptUrl: string` — the `fileUrl` from `/expenses/upload`
- `ocrData: object` — the whole `ocrData` blob from `/expenses/upload`, stored for audit
- `items: ExpenseItemDto[]` — line items

**ExpenseItemDto:**

| Field        | Type     | Required | Notes                                              |
| ------------ | -------- | -------- | -------------------------------------------------- |
| `description`| string   | yes      | What the line is for. Copy OCR `item.name` verbatim |
| `quantity`   | number   | no       | Units, decimals OK (e.g. `2.5` hours)              |
| `unitPrice`  | number   | no       | Price per unit (net)                               |
| `vatRate`    | number   | no       | Percent: `0`, `5`, `8`, or `23` (Polish rates). Default `23` if OCR didn't return it |
| `totalNet`   | number   | yes      | Line net                                           |
| `totalVat`   | number   | yes      | Line VAT amount                                    |
| `totalGross` | number   | yes      | Line gross                                         |

On update (`PUT /expenses/:id`) with `items` in the body: existing items are deleted and replaced with the new array. To keep items unchanged, omit `items` from the update payload.

## Status model

- `UNPAID` (default) — expense is recorded but not paid
- `PAID` — marked paid via `/mark-paid`; sets `paymentDate`, `paymentMethod`, `bankAccountId`

`paymentMethod` is a string (free text); common values used in the UI: `bank_transfer`, `cash`, `card`. `bankAccountId` links to `BankAccount` — get one from `/bank-accounts`. Use an account with `isCash: true` for cash payments.

## Common pitfalls

- **Items' `totalVat` is not in the OCR** — always compute it. The API enforces `totalVat` as required in `items[]`.
- **`amount` is gross, not net** — a frequent mistake when reading the OCR `totals` object.
- **Supplier NIP has 10 digits, no dashes.** If the OCR returned `"123-456-78-90"`, strip non-digits before passing to `/suppliers/search`.
- **Polish dates in the PDF might be `DD.MM.YYYY`** — the OCR normalizes to ISO, but verify before POSTing. The API requires ISO.
- **Do not send empty strings for optional fields** — omit them entirely. `invoiceNumber: ""` will be stored as `""`, not `null`.
- **Dates without a timezone offset are accepted** for `date` and `dueDate` — the API treats them as UTC midnight.
