# Workflow: add a product

Typical request: "добавь продукт Dorsz filet 1kg, 45 zł, категория Рыба", "dodaj produkt ...", "create a product X". See `reference/products.md` for the full DTO.

## Step 1. Collect the fields

Required from the user or the request:
- **Name** (Polish or PL/RU mixed — preserve casing and diacritics)
- **Category** — a phrase like "Рыба" / "Produkty / Ryby" / "Mrożonki"
- **Unit** — `kg`, `szt.`, `l`, `opak.`, …
- **Price (optional)** — net PLN default sale price

Nice-to-have if the user mentions them: `weight`, `vatRate`, `minStock`, `barcode`, `description`, explicit `sku`.

If the user left anything ambiguous (e.g. "добавь dorsz" with no unit/category), **ask** — one short question, group the missing fields. Don't invent values.

## Step 2. Check for duplicates

Before creating, see if a similar product already exists:

```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/products/search?q=<name>"
```

- **Exact or near-exact name match** → show the user the existing product and ask: "This already exists — should I update it instead?" If yes, switch to `workflows/update-product.md`.
- **Similar but clearly different (e.g. *Dorsz filet 1kg* vs. *Dorsz tusza 2kg*)** → continue to create, but mention the near-match in the preview.

## Step 3. Resolve `categoryId`

```bash
bash "$SKILL_DIR/scripts/api.sh" GET /categories/tree
```

Find the branch that matches the user's phrase. Show it as a path (`Продукты › Рыба › Замороженная`) in the preview so the user can correct you.

- **Multiple plausible branches** → show top 2–3 and ask.
- **No branch matches** → ask: "I don't see a category for *<phrase>*. Create a new category or pick an existing branch?" **Don't silently POST `/categories`.**
  - If the user wants a new category: confirm `name` + optional `parentId` (from the tree), then `POST /categories`.

## Step 4. Resolve `unitId`

```bash
bash "$SKILL_DIR/scripts/api.sh" GET /units
```

Match by `abbreviation`. Common: `kg`, `szt.`, `l`, `opak.`, `karton`. Ask if the user's phrase is ambiguous.

## Step 5. Build the payload

```jsonc
{
  "name": "Dorsz filet 1kg",
  "categoryId": "<UUID from step 3>",
  "unitId": "<UUID from step 4>",
  "priceNet": 45.00,
  "vatRate": 8,
  "minStock": 5,
  "description": "Świeży, mrożony"
}
```

Omit `sku` unless the user gave one — the API auto-slugifies from `name` and uniquifies.

## Step 6. Preview and confirm

Summarize in the user's language:
- **Name** — verbatim
- **Category path** — full breadcrumb
- **Unit** — `abbreviation (name)`
- **Price / VAT** — e.g. `45.00 PLN netto, VAT 8%`
- **Other fields** — only if set

Ask: "Create this product?"

## Step 7. POST

```bash
cat > /tmp/product-payload.json <<'EOF'
{ ... payload ... }
EOF

bash "$SKILL_DIR/scripts/api.sh" POST /products -d @/tmp/product-payload.json
```

Response: 201 with the full product incl. the auto-generated `sku` and assigned `id`.

## Step 8. Show the result

- "Created: `Dorsz filet 1kg` (SKU `dorsz-filet-1kg`). Link: `<FRESHFORK_URL>/products/<id>`"

Read `FRESHFORK_URL` from `~/.freshfork/config`.

## Edge cases

- **User asked to "import 20 products from this spreadsheet"** — out of scope. Ask them to paste a list and create one by one, or redirect them to the web UI import (if any).
- **User gave a purchase price, not a sale price** — `priceNet` is the default *sale* price. Don't use a supplier-invoice price for it. Either ask "is 45 PLN the price you'll charge customers, or the cost from the supplier?" or omit `priceNet` entirely.
- **Duplicate SKU on create** — API returns 409. If you passed an explicit SKU, retry with a different one or omit `sku` to let the API generate.
- **Unit not in the dictionary** — the CRM has no `POST /units` endpoint; the unit list is seeded. If nothing fits, ask the user to pick the closest match (e.g. treat `litr` → `l`, `paczka` → `opak.`). Adding a new unit needs a DB seed change — flag it to the user instead of silently picking a wrong one.
