# Changelog

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
- Plugin marketplace moved to a dedicated public GitLab repo: https://gitlab.com/freshforkpublic/claude-skills
- Users install via `/plugin marketplace add https://gitlab.com/freshforkpublic/claude-skills.git` then `/plugin install freshfork-crm@freshfork`.

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
