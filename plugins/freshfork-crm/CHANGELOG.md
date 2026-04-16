# Changelog

## 0.1.0 — 2026-04-16

Initial scaffold, packaged as a **Claude plugin** (works in both Claude Code CLI and Cowork).

- Plugin layout: `.claude-plugin/plugin.json` at the root, skill under `skills/freshfork-crm/`
- `skills/freshfork-crm/SKILL.md` with the map, auth rules, and general conventions
- `skills/freshfork-crm/reference/clients.md` — clients module
- `skills/freshfork-crm/workflows/add-client-by-nip.md` — create a client from a Polish NIP using the Ministry of Finance Whitelist API
- `skills/freshfork-crm/scripts/api.sh` — curl wrapper with Bearer auth and `/api/v1` prefix
- `skills/freshfork-crm/scripts/login.sh` — device-code login flow: opens the browser, user approves on `/settings/connect-cli`, script saves PAT to `~/.freshfork/config`
- `skills/freshfork-crm/scripts/pl-company-lookup.sh` — look up a Polish company by NIP (no API key required)

Backend changes that ship alongside (in `apps/api`):
- `ApiToken` + `CliAuthRequest` Prisma models
- `api-tokens` module (`POST`/`GET`/`DELETE /api-tokens`)
- PAT validation wired into the global `JwtAuthGuard`
- Device-code endpoints: `POST /auth/cli/start`, `GET /auth/cli/status`, `GET /auth/cli/describe`, `POST /auth/cli/approve`

Frontend changes (in `apps/web`):
- `/settings/connect-cli` approval page with `settings.connectCli.*` translations in `ru.json` and `en.json`

Distribution (in `apps/api`):
- `plugins` module — `GET /public/plugins/marketplace.json` returns a marketplace index with one entry per `<plugin>.git/` directory found under `PLUGINS_DIR`
- `main.ts` — serves `PLUGINS_DIR` as static content at `/api/v1/public/plugins/*`, which covers:
  - Git dumb-HTTP: Claude Code installs plugins via `git clone https://crm.similar.group/api/v1/public/plugins/<plugin>.git`
  - Raw tarballs (for manual inspection / download)
- Configurable via env: `PLUGINS_DIR`, `PUBLIC_BASE_URL`, `PLUGINS_MARKETPLACE_{NAME,OWNER,EMAIL}`

Build tooling:
- `packages/crm-skill/tools/build-bundle.sh` — produces three artifacts per run:
  - flat tarball at `<repo>/plugins-dist/<plugin>/<version>.tar.gz`
  - sidecar `<repo>/plugins-dist/<plugin>/meta.json` (description for marketplace)
  - **bare git repo** at `<repo>/plugins-dist/<plugin>.git/` with `git update-server-info` — this is what Claude clones from
- `npm run bundle` in the plugin package

Install URL (production): `https://crm.similar.group/api/v1/public/plugins/marketplace.json`

TODO:
- CI that auto-runs `npm run bundle` on tag push + commits `plugins-dist/` (or uploads via SSH to the server)
- admin page `/settings/api-tokens` (list, create, revoke) for non-CLI use
- reference files for the remaining modules: orders, products, warehouse, purchases, sales, finance, reports, tasks, integrations
- more workflow files: create-order, stocktake, OCR-invoice
