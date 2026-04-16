# Clients

Clients module (B2B counterparties). A client is a company with a NIP/REGON, one or more contacts, one or more delivery addresses, and commercial settings (payment term, credit limit, discount, delivery zone).

## Endpoints

| Method | Path                 | Purpose                                                      |
| ------ | -------------------- | ------------------------------------------------------------ |
| GET    | `/clients`           | Paginated list with filters                                  |
| GET    | `/clients/search?q=` | Quick search by name or NIP (for autocomplete; returns an array) |
| GET    | `/clients/:id`       | Get client by UUID (includes contacts and addresses)         |
| POST   | `/clients`           | Create a client (optionally with contacts and addresses)     |
| PUT    | `/clients/:id`       | Full update                                                  |
| DELETE | `/clients/:id`       | Soft delete (sets `isActive=false`)                          |

Full schemas are in Swagger, tag `Clients`.

## Key fields

### CreateClientDto (POST)

**Required:**
- `companyName: string` — legal name, min 1 character. Example: `"Firma ABC Sp. z o.o."`

**Optional — identification:**
- `nip: string` — Polish NIP, 10 digits, no dashes. Example: `"8993025824"`. Strongly recommended — without it you cannot issue a VAT invoice.
- `regon: string` — REGON (9 or 14 digits)
- `clientGroupId: UUID` — client group (for segmentation and pricing policies)

**Optional — commercial:**
- `paymentTermDays: number` — payment term in days, default `14`
- `creditLimit: number` — credit limit in PLN (plain number)
- `discount: number` — global discount percentage, `0..100`
- `deliveryZone: string` — delivery zone label (used by logistics)
- `notes: string` — free-form notes

**Nested (optional):**
- `contacts: CreateContactDto[]` — contact persons
- `addresses: CreateAddressDto[]` — delivery / legal addresses

### CreateContactDto

- `name: string` (required)
- `position?, email?, phone?: string`
- `isPrimary?: boolean` — primary contact (one per client)

### CreateAddressDto

- `name: string` (required) — address label, e.g. `"Warszawa - magazyn"` or `"Siedziba"`
- `street, city, postalCode: string` (required)
- `country?: string` — defaults to `"PL"`
- `isDefault?: boolean` — default address (one per client)
- `notes?: string`

### ClientQueryDto (GET /clients)

Extends `PaginationDto` (`page`, `perPage`, `search`).

- `clientGroupId?: UUID` — filter by group
- `isActive?: boolean` — active only / deleted only

## Permissions

- `clients.view` — GET
- `clients.create` — POST
- `clients.edit` — PUT
- `clients.delete` — DELETE

If the API returns `403`, the user lacks the permission — tell them. Do not try to work around it.

## Common errors

- **`400` on POST with a duplicate NIP**: ideally the API should return `409 Conflict`, but validation can be subtle — before every POST run `GET /clients/search?q=<NIP>`. If the result is non-empty, ask the user whether they really want to create a duplicate.
- **`404` on PUT/GET/DELETE**: invalid UUID or already-deleted client. `ParseUUIDPipe` rejects malformed UUIDs earlier with `400`.
- **Empty result on `/clients/search?q=...`**: search covers `companyName` and `nip` with Polish diacritics (ł, ś, ą, etc.). Try a partial name.

## Examples

**Find a client by NIP:**
```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/clients/search?q=8993025824"
```

**Create a client with one contact and one address:**
```bash
bash "$SKILL_DIR/scripts/api.sh" POST /clients -d '{
  "companyName": "Firma ABC Sp. z o.o.",
  "nip": "8993025824",
  "paymentTermDays": 14,
  "contacts": [
    { "name": "Jan Kowalski", "email": "jan@abc.pl", "phone": "+48600100100", "isPrimary": true }
  ],
  "addresses": [
    { "name": "Siedziba", "street": "ul. Kwiatowa 1", "city": "Warszawa", "postalCode": "00-001", "isDefault": true }
  ]
}'
```

**Update the payment term:**
```bash
bash "$SKILL_DIR/scripts/api.sh" PUT /clients/<uuid> -d '{"paymentTermDays": 21}'
```

## Related

- `orders` — client orders (see `reference/orders.md`)
- `sales/deals` — sales pipeline; each deal can be linked to a client (see `reference/sales.md`)
- `finance/expenses` — payments; typically linked through orders, not directly to a client
