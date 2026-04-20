# Workflow: update a product

Typical request: "измени цену на Dorsz до 48 zł", "zmień VAT u tego produktu", "подними мин. остаток до 10 шт.", "скрой этот товар из каталога". See `reference/products.md` for `UpdateProductDto`.

**Not supported:** deleting products. If the user asks to "удалить" / "delete" / "usuń" a product, propose `isActive: false` instead (hides from selectors, keeps history). Only execute a real DELETE if the user explicitly acknowledges it'll break historical records — and even then, do it from the web UI, not the skill.

## Step 1. Find the product

From the phrasing — usually a partial name, SKU or barcode.

```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/products/search?q=<name-or-sku>"
```

- **Exactly one result** → use it.
- **Multiple results** → show `name / sku / unit` and ask which one.
- **Zero results** → broaden the query (drop a word), try again. If still nothing, tell the user — don't guess. The user may have meant a product that doesn't exist yet (see `workflows/add-product.md`).

For the full current state of the product (current price, category, VAT, stock):

```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/products/<id>"
```

## Step 2. Figure out which fields change

Map the user's phrasing to DTO fields. Common ones:

| User's phrasing                                       | DTO field       | Notes |
| ----------------------------------------------------- | --------------- | ----- |
| "цена", "price", "cena"                               | `priceNet`      | Net PLN, default sale price |
| "VAT", "налог"                                        | `vatRate`       | Polish rates: 0, 5, 8, 23 |
| "минимальный остаток", "min stock", "stan minimalny"  | `minStock`      | Decimal, re-order threshold |
| "вес", "weight", "waga"                               | `weight`        | kg, decimal |
| "штрихкод", "barcode", "kod kreskowy"                 | `barcode`       | EAN/GTIN |
| "название", "name", "nazwa"                           | `name`          | Preserve user's casing / diacritics |
| "описание", "description", "opis"                     | `description`   | |
| "категория", "category", "kategoria"                  | `categoryId`    | Resolve via `/categories/tree` — see `add-product.md` step 3 |
| "единица", "unit", "jednostka"                        | `unitId`        | Resolve via `/units` — see `add-product.md` step 4 |
| "фото", "image", "zdjęcie"                            | `imageUrl`      | Absolute URL |
| "скрой", "сделай неактивным", "hide", "deactivate", "usuń" | `isActive: false` | **Use this instead of DELETE** |
| "активируй снова", "restore", "przywróć"              | `isActive: true`| |
| "SKU", "код"                                          | `sku`           | Uniqueness enforced |

**If the request is vague** — e.g. "обнови этот продукт" with no specifics — ask what exactly to change before loading the product.

## Step 3. Build a partial payload

Pass **only the changing fields** — the API merges partial updates.

```jsonc
// price change
{ "priceNet": 48.00 }

// rename + VAT
{ "name": "Dorsz filet 1kg (świeży)", "vatRate": 8 }

// hide from catalog (the "don't delete" path)
{ "isActive": false }
```

Don't re-send fields that aren't changing. The API doesn't require them and any mismatch risks clobbering a value the user didn't mean to touch.

## Step 4. Preview + confirm

Show the user:
- **Product** — `name (SKU)`
- **Changes** — `<field>: <before> → <after>` for each field
- **No-op fields** — omit entirely, don't clutter the preview

Ask: "Apply these changes?"

For a hide request, spell out the consequence: "This will set `isActive: false`. The product disappears from selectors and search, but existing orders/invoices/stock rows keep working. Confirm?"

## Step 5. PUT

```bash
cat > /tmp/product-update.json <<'EOF'
{ ... partial payload ... }
EOF

bash "$SKILL_DIR/scripts/api.sh" PUT /products/<id> -d @/tmp/product-update.json
```

Response: the full updated product.

## Step 6. Show the result

- "Updated `Dorsz filet 1kg`: priceNet 45.00 → 48.00 PLN"
- For hide: "`Dorsz filet 1kg` is now inactive. Link: `<FRESHFORK_URL>/products/<id>`"

## Edge cases

- **User asked to "delete" a product** — refuse the destructive action. Offer `isActive: false`. If they insist on a real DELETE, tell them it'll break historical orders/invoices/stock and redirect them to do it manually from the web UI with a DBA's help.
- **Price edit where the user gave gross instead of net** — `priceNet` is net. If the user said "48 brutto", compute net: `gross / (1 + vatRate/100)`. Confirm the computed net before PUTting.
- **Category change that moves the product to a different tree branch** — the category of a product with existing stock is fine to change; stock rows stay with the product. But confirm with the user — a category move affects reports.
- **SKU collision on update** — if the user changes `sku` to one that already exists, API returns 409. Tell the user and ask for a different code.
- **Reactivating a hidden product** — single-field `PUT {"isActive": true}`. The product returns to selectors immediately; no data recovery needed (the row was never deleted).
