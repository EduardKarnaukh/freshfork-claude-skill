# Products, categories, units of measure

Products are the master data behind orders, purchase invoices, PZ documents and stock. Every product belongs to exactly one `Category` (tree with `parentId`) and one `Unit` (kg, szt., l, opak., …).

**Rule for this skill:** you can **create** and **update** products, categories and units. You must **not delete** them. Deleting master data breaks historical orders, PZs and stock movements — if the user asks to delete, propose either renaming or setting `isActive: false` (update) instead.

## Endpoints

### Products

| Method | Path                        | Purpose                                                          |
| ------ | --------------------------- | ---------------------------------------------------------------- |
| GET    | `/products`                 | Paginated list (filters: `search`, `categoryId`, `isActive`)     |
| GET    | `/products/search?q=<term>` | Flat list for selectors; returns `{id, name, sku, unit:{id, abbreviation}}`. Diacritics- and case-insensitive (`zurawina 1 kg` finds `Żurawina mrożona 1 KG`). Only `isActive` products |
| GET    | `/products/:id`             | Full product incl. category, unit, prices, stock                 |
| POST   | `/products`                 | Create                                                           |
| PUT    | `/products/:id`             | Update (also the way to toggle `isActive: false` — soft hide)    |
| ~~DELETE~~ | ~~`/products/:id`~~     | **Don't call from the skill.** Breaks historical records. Use `PUT {isActive: false}` instead |

### Categories

| Method | Path                | Purpose                                                  |
| ------ | ------------------- | -------------------------------------------------------- |
| GET    | `/categories`       | Paginated list (filter: `search`)                        |
| GET    | `/categories/tree`  | Hierarchical tree. **Use this when matching a category** — easier to read than the flat list |
| GET    | `/categories/:id`   | Get by UUID                                              |
| POST   | `/categories`       | Create (optionally with `parentId` to nest under another)|
| PUT    | `/categories/:id`   | Update                                                   |

### Units

| Method | Path        | Purpose                                            |
| ------ | ----------- | -------------------------------------------------- |
| GET    | `/units`    | Flat list of all units (no pagination). Stable dictionary — create new units rarely |

A unit has `{id, name, abbreviation, isDefault}`. Common entries: `kg`, `szt.`, `l`, `opak.`, `karton`.

Full schemas in Swagger, tags `Products`, `Categories`, `Units`.

## Key fields — CreateProductDto

**Required:**
- `name: string` — human name in the user's language. Product names in this CRM are Polish or mixed Polish/Russian; preserve what the user typed
- `categoryId: UUID` — must exist in `/categories`
- `unitId: UUID` — must exist in `/units`

**Optional:**
- `sku: string` — if omitted, the API auto-generates one from the name (slugified). Pass an explicit SKU only when the user has a specific code to use. Unique across the table
- `description: string` — free-form
- `weight: number` — in kg, decimal
- `vatRate: number` — percent. Polish rates: `0`, `5`, `8`, `23`. Default `23`
- `minStock: number` — re-order threshold (used by stock alerts)
- `priceNet: number` — default sale price (net PLN). The CRM also supports client-specific prices (`ProductPrice`), but those live on a separate endpoint
- `barcode: string` — EAN/GTIN or free-form
- `imageUrl: string` — absolute URL (MinIO or external)

**Not in the DTO:**
- `isActive` — only on `UpdateProductDto`. A new product is always created active. To hide one without deleting, use `PUT {isActive: false}`

## UpdateProductDto

Extends `CreateProductDto` as `Partial<CreateProductDto>` + `isActive: boolean`. Pass **only the fields that change** — the API merges partial updates, so sending the whole object back isn't needed.

```jsonc
// Change price only
PUT /products/<id>  { "priceNet": 28.00 }

// Rename + change VAT
PUT /products/<id>  { "name": "Dorsz filet 1kg (świeży)", "vatRate": 8 }

// Hide product from selectors without deleting
PUT /products/<id>  { "isActive": false }
```

## CreateCategoryDto

**Required:**
- `name: string`

**Optional:**
- `slug: string` — auto-generated from name if omitted. Must match `/^[a-z0-9-]+$/` (lowercase, digits, hyphens)
- `parentId: UUID` — nest under another category (e.g. "Рыба" under "Продукты")
- `sortOrder: int` — display order; default `0`
- `imageUrl: string`

## Matching category + unit (for create-product flow)

### Category
Load the tree once, keep it in the chat:

```bash
bash "$SKILL_DIR/scripts/api.sh" GET /categories/tree
```

The tree returns a nested structure `[{id, name, children: [...]}]`. Pick the most specific branch that matches the product. Show the user the top 1–3 candidates with their path (e.g. `Продукты › Рыба › Замороженная`). Don't create a new category without asking.

### Unit
Load all units:

```bash
bash "$SKILL_DIR/scripts/api.sh" GET /units
```

Match by `abbreviation` first (`kg`, `szt.`, `l`, `opak.`), fall back to `name`. If the user says "3 kg filet łososia", the unit is `kg`. If they say "5 opakowań ..." — `opak.`. Ask if ambiguous.

## SKU generation rules

When `sku` is omitted on create, the API slugifies the name and ensures uniqueness (appends `-1`, `-2`, … on collisions). You can predict the first candidate: `Łosoś filet 1kg` → `losos-filet-1kg`. Prefer letting the API generate — user-typed SKUs are error-prone. Override only when the user has a real code (e.g. from Fakturownia or a supplier catalog).

## Common pitfalls

- **Don't `POST /categories` or `POST /units` as a side-effect.** If a product doesn't fit any category, ask the user whether to create a new category — that's a separate decision. Same for units.
- **Don't call `DELETE /products/:id`** from the skill. Use `PUT {isActive: false}` to hide. Historical PZs, orders and stock rows keep working.
- **`vatRate` on a product vs. on an invoice line** — the product holds the *default* rate, but `PurchaseInvoiceItemDto.vatRate` and `ExpenseItemDto.vatRate` can override per-invoice. Don't edit the product VAT just because one invoice had a different rate.
- **`priceNet` is a default sale price**, not the purchase price. Don't update it from purchase invoice data; purchase prices are tracked elsewhere (product–supplier link).
- **Polish characters** — names stored as typed (`Żurawina`, `Łosoś`, `Mąka`). The search endpoint handles diacritics; you don't need to strip them.
- **`isActive: false` ≠ deletion.** The product still exists, is hidden from selectors, keeps its history. Re-activate via `PUT {isActive: true}`.
