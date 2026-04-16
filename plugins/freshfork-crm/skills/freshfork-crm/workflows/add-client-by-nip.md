# Workflow: add a client by NIP

Typical request: "add a client by NIP 8993025824", "create counterparty 8993025824", "заведи клиента по НИПу ...".

This is a **core flow** — apply it whenever the user asks to "add company X to the CRM".

Company lookup is handled server-side: the CRM forwards to the Polish GUS BIR1 registry and normalizes the response. You don't call external APIs — one authenticated endpoint covers it.

## Steps

### 1. Check for duplicates in the CRM
```bash
bash "$SKILL_DIR/scripts/api.sh" GET "/clients/search?q=<NIP>"
```
If the array is non-empty — **stop**, show the match to the user and ask:
- "There's already a client with this NIP: `<companyName>`. Create a duplicate, or update the existing one?"

### 2. Fetch company data from GUS via the CRM
```bash
bash "$SKILL_DIR/scripts/api.sh" POST /integrations/gus/lookup -d '{"nip":"<NIP>"}'
```
Response shape (see `reference/clients.md` → GUS lookup):
- `companyName` — legal name
- `nip`, `regon`, `krs`
- `street`, `postalCode`, `city`, `country` — already parsed fields, **no regex needed**
- `email`, `phone` — sometimes present

**Error handling:**
- `404` → company not found in GUS. Ask the user whether to create it manually with only the NIP.
- `503` with "GUS integration is not configured" → admin needs to set `GUS_API_KEY` in the API `.env`. Stop, tell the user.
- `503 rate limit` → retry in a few seconds; if still failing, stop and tell the user.
- `400 Provide at least one of nip, regon, krs` → you passed an empty body; pass `nip`.

### 3. Show the user and wait for confirmation
Summarize briefly:
- Name, NIP, full address, REGON/KRS if present
- What exactly you'll POST to the CRM (the fields `companyName`, `nip`, `regon`, `addresses[0]`)
- Ask: "Create it?"

### 4. POST /clients
```bash
bash "$SKILL_DIR/scripts/api.sh" POST /clients -d '{
  "companyName": "<companyName from GUS>",
  "nip": "<nip>",
  "regon": "<regon>",
  "addresses": [
    { "name": "Siedziba", "street": "<street>", "city": "<city>", "postalCode": "<postalCode>", "country": "PL", "isDefault": true }
  ]
}'
```

- Omit any field GUS didn't return (don't send empty strings).
- Do not auto-add contacts — the user will enter them separately or you'll ask.

### 5. Show the result
Created client: `id`, `companyName`, and a UI link: `<FRESHFORK_URL>/clients/<id>` (read `FRESHFORK_URL` from `~/.freshfork/config`).

## Edge cases

- **NIP is not 10 digits** — ask again; there may be dashes or spaces. Normalize: strip non-digits, expect exactly 10.
- **GUS returns `404`** — no company with this NIP, or it has been deregistered. Ask the user whether to create it with only `companyName` + `nip`.
- **Company found but no street/city** (sole proprietors sometimes have only the address of the individual) — create with `companyName` + `nip` only, ask the user to fill the address later.
- **Client already in CRM** — do not create; offer `PUT /clients/<id>` to update instead. Addresses are a separate nested resource.

## Why GUS (not Whitelist or VIES)

- **GUS BIR1** (what we use): official Polish company registry. Returns legal name, NIP, REGON, KRS, address with separate street/postalCode/city fields, sometimes email/phone. Requires a registered API key on the CRM side (`GUS_API_KEY`).
- **Whitelist (wl-api.mf.gov.pl)**: free, no key, returns VAT status + single-string address + bank accounts. Less data, and needs client-side parsing. We don't use it here.
- **VIES**: EU-wide VAT status check only, no address. Not enough for a full client record.
