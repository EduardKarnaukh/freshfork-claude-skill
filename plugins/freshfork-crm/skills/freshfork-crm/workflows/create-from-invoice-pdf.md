# Workflow: create an expense or a purchase invoice from a PDF/photo

Typical request: user drops a PDF or photo of an invoice in the chat ("добавь расход по этой фактуре", "dodaj fakturę", "заведи эту накладную"). **You read and match everything yourself — no server-side OCR, no backend fuzzy search.** Parse the attachment with the Read tool (it handles PDFs and images), match suppliers and products in your own context, then POST the finished payload. The endpoints `/expenses/upload` and `/purchase-invoices/upload` run OpenAI OCR server-side and are for the web UI only — skip them.

This is a **single unified flow**. Step 2 decides whether the document is an operational expense (phone, internet, rent, services) or a purchase invoice for goods that hit stock (and should spawn a PZ receipt document). From step 5 the flow branches.

Field schemas live in `reference/finance.md` (expenses) and `reference/purchases.md` (purchase invoices + PZ). Don't duplicate them here.

## Step 1. Read the attachment

The attachment has a local path in the chat environment. Read it:

```
Read: /path/to/invoice.pdf
```

**Fields to extract (Polish VAT invoice = *faktura VAT*):**

| Where on the invoice                      | What it maps to                     | Notes |
| ----------------------------------------- | ----------------------------------- | ----- |
| Title line: *Faktura VAT nr FV/2026/001*  | `invoiceNumber`                     | Copy verbatim, including prefix and slashes |
| *Data wystawienia* / *Date of issue*      | `invoiceDate` / `date`              | Convert `DD.MM.YYYY` → ISO `YYYY-MM-DD` |
| *Termin płatności* / *Due date*           | `dueDate`                           | ISO. Omit if not on the doc |
| *Sprzedawca* section → company name       | supplier match input                | Full legal name |
| *Sprzedawca* section → NIP                | supplier match input                | Strip non-digits, expect 10 |
| *Razem netto / VAT / brutto* totals row   | `totalNet`, `totalVat`, `totalGross` (or `amount` for expenses — gross) | |
| Currency (*PLN*, *EUR*, …)                | `currency`                          | ISO 3-letter; default PLN if unspecified |
| Line items table (*Lp.*, *Nazwa*, *Ilość*, *Cena jedn. netto*, *VAT %*, *Wartość netto*, *Wartość brutto*) | `items[]` | One row per line |
| *Uwagi* / notes                           | `description` / `notes`             | Short memo. If absent, write one yourself ("Hostinger — kwiecień 2026") |

Leave out fields that genuinely aren't on the document — don't guess.

## Step 2. Classify: expense or purchase invoice?

**Border rule:** affects stock? → purchase invoice. Doesn't? → expense.

### Obvious EXPENSE (proceed without asking)

Any of these strongly imply a pure service expense:

- Telecom / internet (*telefon*, *internet*, *abonament*, T-Mobile, Orange, Play, Plus, Netia)
- Hosting / domain / SaaS (*hosting*, *domena*, *abonament*, Hostinger, OVH, AWS, Google Workspace, Atlassian, GitHub)
- Rent (*czynsz*, *najem*)
- Utilities (*prąd*, *gaz*, *woda*, *media*, PGE, Tauron, PGNiG, Veolia)
- Insurance (*ubezpieczenie*, PZU, Warta, Allianz)
- Accounting / legal / consulting (*księgowość*, *biuro rachunkowe*, *prawnik*, *doradztwo*)
- Fuel / transport (*paliwo*, *benzyna*, Orlen, Shell, BP, *transport*, *kurier*, InPost, DPD, DHL)
- Advertising (*reklama*, Google Ads, Facebook Ads, Meta)
- Bank fees (*prowizja bankowa*, *opłata*)

Signal: single-line or a few-line service invoice, unit of measure is abstract (*szt.*, *usługa*, *miesiąc*) or just `1`.

### Obvious PURCHASE INVOICE (proceed without asking)

Any of these strongly imply goods-for-stock:

- Food ingredients (*mięso*, *ryba*, *warzywa*, *mąka*, *olej*, *przyprawy*, *nabiał*, *pieczywo*) — Freshfork is a food franchise, kitchen supplies hit stock
- Packaging (*opakowania*, *pudełka*, *folia*, *torby*)
- Beverages for resale (*napoje*, *piwo*, *wino*, *soki*)
- Multiple line items with physical units (*kg*, *l*, *szt.* with quantity > 1, *opak.*, *karton*)
- **At least one item matches a product in the CRM catalog** (`/products/search?q=<item-name>` returns a hit)

### Unclear → ASK

Ask the user **when any of these hold**:

- Mixed line items: some look like services, others like goods
- Goods that *don't* match any product in the catalog *and* aren't obviously for stock (office supplies, tools, fixed assets like a fridge or an oven)
- Confidence is low (scan quality, handwritten amounts)

**How to ask.** One short summary + the key signal + both options in the user's language. Example:

> "Invoice from *Hurtownia Smakosz*, 4 items (dorsz 5kg, łosoś 3kg, opakowania 100szt., etykiety 500szt.) — looks like goods for stock. Create as a **purchase invoice with a PZ receipt document** (updates stock), or as a plain **expense**?"

> "Invoice from *Allegro Sp. z o.o.* — one line '*Piekarnik elektryczny*' 1 szt., 3500 PLN. That's equipment, not stock. Record as a plain **expense** (OFFICE/EQUIPMENT category)? Or a **purchase invoice** if you want it in the product catalog?"

Don't ask when the answer is obvious — the user called out "płatność za telefon to po prostu wydatek".

## Step 3. Attach the file (same for both branches)

```bash
bash "$SKILL_DIR/scripts/upload-receipt.sh" /path/to/invoice.pdf
```

Response: `{ "fileUrl": "..." }`. Save `fileUrl` — it goes into `receiptUrl` (expense) or `fileUrl` (purchase invoice). The endpoint stores under `expenses/` regardless — the path is fine for both record types; we reference the URL, not the folder.

## Step 4. Match the supplier (same for both branches)

```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/suppliers/search?q=<NIP>"
```

- **Array has a match** → use the first element's `id` as `supplierId`.
- **Empty array with NIP + name present** → ask: "This supplier isn't in the CRM yet — shall I create it via GUS lookup?" If yes:
  ```bash
  bash "$SKILL_DIR/scripts/api.sh" POST /suppliers/gus-lookup -d '{"nip":"<nip>"}'
  # → preview to user → POST /suppliers with the merged data
  ```
  See `reference/purchases.md` for `CreateSupplierDto`.
- **No NIP** → try `GET /suppliers/search?q=<company-name>`. If ambiguous, show top 3 matches and let the user pick.
- **Nothing** →
  - For **expense**: omit `supplierId`. It's optional.
  - For **purchase invoice**: `supplierId` is *required*. Create the supplier first (companyName at minimum), then continue.

## Step 5A — EXPENSE branch

### 5A.1 Pick the category

```bash
bash "$SKILL_DIR/scripts/api.sh" GET /expense-categories
```

Each row: `id`, `name`, `code`, optional `parentId`, `budgetMonthly`. Infer from invoice content:

| Invoice content hints                             | Likely `code`            |
| ------------------------------------------------- | ------------------------ |
| telefon, internet, abonament                      | `TELECOM` or `IT`        |
| czynsz, najem                                     | `RENT`                   |
| prąd, gaz, woda, media                            | `UTILITIES`              |
| hosting, domena, saas, licencja                   | `IT` or `SERVICES`       |
| paliwo, benzyna, transport, kurier                | `TRANSPORT`              |
| reklama, marketing, google ads, facebook          | `MARKETING`              |
| księgowość, prawnik, consulting                   | `PROFESSIONAL_SERVICES`  |
| biuro, papier, materiały biurowe                  | `OFFICE`                 |
| ubezpieczenie                                     | `INSURANCE`              |

Weak hint? Show top 2–3 candidates and ask.

### 5A.2 Build the expense payload

See `reference/finance.md` for the full `CreateExpenseDto`. Core shape:

```jsonc
{
  "categoryId": "<UUID from 5A.1>",
  "amount": 123.00,                         // gross total
  "currency": "PLN",
  "date": "2026-04-17",                     // invoice date, not today
  "description": "Hostinger — kwiecień 2026",
  "invoiceNumber": "FV/2026/001",
  "supplierId": "<UUID from step 4, or omit>",
  "dueDate": "2026-05-01",                  // omit if not on the invoice
  "totalNet": 100.00,
  "totalVat": 23.00,
  "receiptUrl": "<fileUrl from step 3>",
  "items": [
    { "description": "Hosting — 1 miesiąc",
      "quantity": 1, "unitPrice": 100.00, "vatRate": 23,
      "totalNet": 100.00, "totalVat": 23.00, "totalGross": 123.00 }
  ]
}
```

Per-item `totalVat` is not on the PDF — derive it as `totalGross - totalNet`. If per-item sums drift by ±0.01 from the invoice totals row, adjust the last line to reconcile.

Do **not** send `ocrData` — that's for the web UI's OCR path.

### 5A.3 Jump to Step 6.

## Step 5B — PURCHASE INVOICE branch

### 5B.1 Pull the catalog, match each line item

**You** do the matching — not the backend's fuzzy search. `/products/search?q=<item-name>` AND-s every token through unaccent+ILIKE, so an extra qualifier like `świeży` or `1 kg` on the invoice can kill a real match. Pull the whole active catalog into your context and match in your head.

**Step A — dump the active catalog in one call:**

```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/products/search?q=&limit=2000"
```

Returns a flat array `[{id, name, sku, unit: {id, abbreviation}}, ...]`. `limit=2000` covers any realistic Freshfork franchisee catalog.

If the catalog has >2000 active SKUs (rare): filter by category first — `GET /categories/tree` → pick the branch the invoice is about → `GET /products?categoryId=<uuid>&isActive=true&perPage=100` paginated until `totalPages`.

**Step B — match each invoice line to a catalog entry.** Use semantic reasoning. Things that matter:

| Aspect          | Rule                                                                 |
| --------------- | -------------------------------------------------------------------- |
| Primary noun    | `dorsz`, `łosoś`, `mąka`, `opakowanie` — what the product IS         |
| Size qualifier  | `1kg` vs `5kg` are different SKUs — **don't** collapse them          |
| Form            | `świeży` vs `mrożony`, `filet` vs `dzwonki` — sub-variants           |
| Diacritics      | `Żurawina` == `Zurawina` — ignore                                    |
| Unit            | kg / szt. / l / opak. — must line up with catalog `unit.abbreviation`; if the invoice line is in kg and the product is sold in szt., that's a red flag |
| SKU in the PDF  | If the invoice line prints a supplier code or SKU, look for an exact `sku` match in the catalog — trumps name matching |

**Step C — show the user a matching table** in their language, with confidence. Example:

```
Line (from PDF)                Qty/Unit   → Matched catalog entry              SKU            Confidence
1. Dorsz filet świeży 1 kg     5 kg         Dorsz atlantycki filet 1kg         DORSZ-ATL-1KG  high
2. Łosoś wędzony               2 szt.       Łosoś wędzony 250g                 LOS-WEND-250   medium
3. Nowa pozycja XYZ            1 szt.       — no match —                       —              —
```

Ask the user to confirm or correct. For each unmatched line:

- **Create a new product** → run the `add-product` workflow (`POST /products` needs `name`, `categoryId`, `unitId` — confirm with the user).
- **Pick one manually** → user gives SKU or name; look it up with `GET /products/search?q=<SKU>`.
- **Skip** → the line is dropped from `items[]`. Invoice totals stay authoritative (financial record is fine), but that item won't land on the PZ and its stock won't increase.

If **zero** items matched overall, warn: "No catalog matches — I can still create the invoice, but there'll be no PZ and no stock change. Proceed?"

### 5B.2 Decide on PZ (auto-create or not)

Ask the user (unless they've already said yes in this session):

> "Create a PZ warehouse receipt too? That posts the items to stock at a warehouse. Yes / no / later."

If **yes**, pick a warehouse:

```bash
bash "$SKILL_DIR/scripts/api.sh" GET /warehouses/active
```

- Single active warehouse → use it, mention it in the preview.
- Multiple → ask the user which one (show `name`, omit UUIDs).

Set on the payload: `autoCreatePZ: true` + `warehouseId: "<uuid>"`.

If **no** / **later** → leave `autoCreatePZ` out (defaults to `false`). You can add a PZ later via `POST /purchase-invoices/<id>/create-pz`.

### 5B.3 Build the purchase invoice payload

See `reference/purchases.md` for the full `CreatePurchaseInvoiceDto`. Core shape:

```jsonc
{
  "invoiceNumber": "FV/2026/001",
  "supplierId": "<UUID from step 4>",       // required
  "invoiceDate": "2026-04-17",
  "dueDate": "2026-05-01",
  "currency": "PLN",
  "totalNet": 1000.00,
  "totalVat": 80.00,
  "totalGross": 1080.00,
  "fileUrl": "<fileUrl from step 3>",
  "notes": "Dostawa z 17.04",
  "type": "INVOICE",                        // or "RECEIPT" for a paragon
  "warehouseId": "<UUID if autoCreatePZ>",  // required when autoCreatePZ=true
  "autoCreatePZ": true,                     // or false — see 5B.2
  "items": [
    { "productId": "<UUID>",
      "quantity": 5, "unitPrice": 18.00, "vatRate": 8 },
    { "productId": "<UUID>",
      "quantity": 3, "unitPrice": 45.00, "vatRate": 8 }
  ]
}
```

Per-item fields: `productId` (UUID of matched product), `quantity` (kg/l/szt), `unitPrice` (net), optional `vatRate` (0/5/8/23, default 23). **No free-form description** — every line hangs off a product.

### 5B.4 Jump to Step 6.

## Step 6. Preview and confirm (both branches)

Summarize in the user's language. Shared:

- **Supplier** — name + NIP (or "none" / "will be created")
- **Invoice** — `#invoiceNumber`, `invoiceDate`, `dueDate` if any
- **Totals** — `netto / VAT / brutto <currency>`
- **Attachment** — "PDF attached: invoice.pdf"

Branch-specific:

- **Expense** — category name; items line-by-line (or "N positions" if many)
- **Purchase invoice** — items matched (e.g. `dorsz 5kg → Dorsz filet 1kg × 5`); PZ plan ("will create PZ at warehouse X" / "no PZ"); any skipped / unmatched lines flagged explicitly

Ask: "Create this expense?" or "Create this purchase invoice (+ PZ)?".

## Step 7. POST

Write the JSON to a temp file first — inline `-d '{...}'` breaks on quotes and UTF-8:

```bash
cat > /tmp/payload.json <<'EOF'
{ ... payload ... }
EOF
```

**Expense:**
```bash
bash "$SKILL_DIR/scripts/api.sh" POST /expenses -d @/tmp/payload.json
```

**Purchase invoice:**
```bash
bash "$SKILL_DIR/scripts/api.sh" POST /purchase-invoices -d @/tmp/payload.json
```

Both return `201` with the full record. For purchase invoices with `autoCreatePZ: true`, the response includes the created PZ id (e.g. `pzDocument: { id, number, status: "CONFIRMED" }`).

## Step 8. Show the result

- Expense: "Created expense `Hostinger — kwiecień 2026`, 123.00 PLN. Link: `<FRESHFORK_URL>/expenses`"
- Purchase invoice (no PZ): "Created purchase invoice #FV/2026/001, 1080.00 PLN. Link: `<FRESHFORK_URL>/purchases`"
- Purchase invoice (with PZ): "Created purchase invoice #FV/2026/001 + PZ `<pz-number>` (stock updated at `<warehouse-name>`). Links: `<FRESHFORK_URL>/purchases`, `<FRESHFORK_URL>/warehouse/documents/<pz-id>`"

Read `FRESHFORK_URL` from `~/.freshfork/config`.

## Edge cases

- **Bad-quality scan** — if a value isn't readable with confidence, put `?` in the preview and ask, don't guess.
- **Multiple VAT rates** — each item keeps its own `vatRate`. Do not collapse.
- **Non-PLN invoice** — set `currency` to the ISO code. The CRM doesn't do FX conversion; amounts stay in the invoice's currency.
- **Receipt (*paragon fiskalny*)** — no NIP of buyer, no line-item VAT breakdown. For the **expense** branch: post with `amount` + `date` + `description` + `categoryId` + `receiptUrl` only; skip `items[]`, `invoiceNumber`, `supplierId`. For the **purchase invoice** branch: pass `type: "RECEIPT"` and still supply supplier + items.
- **Proforma (*faktura proforma* / *zaliczkowa*)** — by convention NOT recorded until the final invoice is issued. Ask: "This is a proforma — still record it?" If no, stop.
- **Corrective invoice (*faktura korygująca*)** — amends an existing invoice. Ask the user which original record to update. For a purchase invoice whose PZ is already confirmed, the PZ must be cancelled and re-issued if quantities change.
- **Duplicate check** — before POSTing:
  ```bash
  bash "$SKILL_DIR/scripts/api.sh" GET "/expenses?search=<invoiceNumber>&perPage=5"
  bash "$SKILL_DIR/scripts/api.sh" GET "/purchase-invoices?search=<invoiceNumber>&perPage=5"
  ```
  Same invoice number + same supplier already in the list → stop and ask.
- **Mixed goods + services on one invoice** — pick the dominant type and ask the user. The CRM can't split one PDF across both modules; the user will need to post the minor part manually afterwards, or adjust line items.

## What NOT to do

- **Don't call `/expenses/upload` or `/purchase-invoices/upload`** — those run server-side OCR. Use `/expenses/receipt-upload` (via `upload-receipt.sh`) for plain file storage in both branches.
- Don't invent `supplierId` or `productId`. Match real records or fail explicitly.
- Don't set `status: "PAID"` on create. Create unpaid; use `PATCH /expenses/:id/mark-paid` for expenses or the purchase payment flow when the user confirms payment.
- Don't pass `autoCreatePZ: true` without `warehouseId` — the API rejects it.
- Don't skip the classifier. A purchase invoice posted as an expense won't update stock and vice versa — both are painful to unwind.
