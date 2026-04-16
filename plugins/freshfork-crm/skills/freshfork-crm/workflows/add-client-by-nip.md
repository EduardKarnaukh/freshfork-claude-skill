# Workflow: add a client by NIP

Typical request: "add a client by NIP 8993025824", "create counterparty 8993025824", "заведи клиента по НИПу ...".

This is a **core flow** — apply it whenever the user asks to "add company X to the CRM".

## Steps

### 1. Check for duplicates in the CRM
```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/clients/search?q=<NIP>"
```
If the array is non-empty — **stop**, show the match to the user and ask:
- "There's already a client with this NIP: `<companyName>`. Create a duplicate, or update the existing one?"

### 2. Fetch company data
Use the Polish Ministry of Finance Whitelist API (free, no API key):
```bash
bash "$SKILL_DIR/scripts/pl-company-lookup.sh" <NIP>
```
The script returns JSON (see the script and `reference/clients.md` for details) with:
- `name` — legal name
- `workingAddress` / `residenceAddress` — address
- `statusVat` — `Czynny` (active), `Zwolniony` (exempt), `Niezarejestrowany` (unregistered)
- `accountNumbers: string[]` — IBAN accounts

If `statusVat != "Czynny"`, warn the user — VAT invoices for a non-active counterparty are problematic.

### 3. Show the user and wait for confirmation
Summarize briefly:
- Name, NIP, address, VAT status
- What exactly you'll POST to the CRM (the fields `companyName`, `nip`, `addresses[0]`)
- Ask: "Create it?"

### 4. Parse the address
The Whitelist API returns the address as a single string, e.g. `ul. Kwiatowa 1, 00-001 Warszawa`. Split it into `street`, `postalCode`, `city`:
- regex: `/^(.+?),\s*(\d{2}-\d{3})\s+(.+)$/` → `$1 = street`, `$2 = postalCode`, `$3 = city`
- if it doesn't parse, put the whole string in `street`, leave `city`/`postalCode` empty, and **warn the user** — they should verify in the UI.

### 5. POST /clients
```bash
bash "$SKILL_DIR/scripts/api.sh" POST /clients -d '{
  "companyName": "...",
  "nip": "...",
  "addresses": [
    { "name": "Siedziba", "street": "...", "city": "...", "postalCode": "...", "country": "PL", "isDefault": true }
  ]
}'
```

Do not auto-add contacts — the user will enter them themselves or you'll ask separately.

### 6. Show the result
Created client: `id`, `companyName`, and a UI link: `${FRESHFORK_URL}/clients/<id>`.

## Edge cases

- **NIP is not 10 digits** — ask again; there may be dashes or spaces. Normalize: `nip.replace(/\D/g, '')`.
- **Whitelist returns `subject: null`** — no company with this NIP, or it has been deregistered. Ask the user whether to create it manually with minimal data.
- **Company found but no address** (common for sole proprietors) — create with `companyName` + `nip` only; the user can add the address later.
- **Multiple `accountNumbers`** — there's currently no place for them in `CreateClientDto`; just show them to the user for reference.
- **Client already in CRM** — do not create; offer `PUT /clients/<id>` to update instead. Addresses are a separate nested resource (see the reference).

## Why Whitelist, not GUS or VIES

- **Whitelist (wl-api.mf.gov.pl)**: free, no API key, returns VAT status (critical for B2B), address, bank accounts. The source of truth for Polish VAT operations.
- **GUS (BIR1.1)**: requires registration and an API key; returns more data (PKD codes, legal form). Upgrade if we need that later.
- **VIES**: EU-wide VAT status check only, no address. Weaker.
