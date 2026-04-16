---
name: freshfork-crm
description: Freshfork CRM — a Polish B2B CRM. Use this skill whenever the user asks to do anything in Freshfork — add/find a client, create an order, check stock, look at sales, manage tasks, purchases, or integrations (Fakturownia, Allegro, Telegram). Polish B2B context — NIP/REGON, Polish companies, PLN.
---

# Freshfork CRM skill

CRM for Polish B2B (franchisee product sales). This skill is a map of the REST API and business workflows. Detailed field schemas live in Swagger — do not duplicate them here.

## How to invoke the shell scripts

Scripts live in `scripts/` next to this `SKILL.md`. Inside a running Claude session the plugin install path is exposed as `${CLAUDE_PLUGIN_ROOT}`:

```bash
# skills directory when installed as a Claude plugin (CLI + Cowork):
SKILL_DIR="${CLAUDE_PLUGIN_ROOT}/skills/freshfork-crm"
```

All examples below use `$SKILL_DIR` as shorthand for that path. If for some reason `$CLAUDE_PLUGIN_ROOT` is unset (e.g. you're reading this file via a raw path during development), derive `SKILL_DIR` from the absolute path of this `SKILL.md` — the Read tool showed it to you.

## Before you start

1. Check that the config exists: `~/.freshfork/config` must contain `FRESHFORK_URL` and `FRESHFORK_TOKEN`. If it doesn't — see the Setup section below.
2. Use `$SKILL_DIR/scripts/api.sh` for every API call:
   ```bash
   bash "$SKILL_DIR/scripts/api.sh" GET /clients?perPage=5
   bash "$SKILL_DIR/scripts/api.sh" POST /clients -d '{"companyName":"..."}'
   ```
   The script reads the config, adds the Bearer header and `/api/v1` prefix, and returns JSON.
3. The full schema for any endpoint is in Swagger: `${FRESHFORK_URL}/api/docs` (JSON at `${FRESHFORK_URL}/api/docs-json`). If the reference files here are not enough — look at Swagger.

## Map

### reference/ — per-module references
- [`reference/clients.md`](reference/clients.md) — clients, contacts, addresses, groups, search by NIP
- `reference/orders.md` — *(TODO)* orders, statuses DRAFT→CONFIRMED→…→INVOICED, comments
- `reference/products.md` — *(TODO)* products, categories, units of measure
- `reference/warehouse.md` — *(TODO)* warehouses, receipt/issue documents, stock movements, production
- `reference/purchases.md` — *(TODO)* suppliers, purchase invoices, OCR
- `reference/sales.md` — *(TODO)* leads, deals, activities, pipeline stages
- `reference/finance.md` — *(TODO)* bank accounts, expenses
- `reference/reports.md` — *(TODO)* sales report and filters
- `reference/tasks.md` — *(TODO)* tasks, statuses, kanban
- `reference/integrations.md` — *(TODO)* Fakturownia (invoicing), Allegro, Telegram, OpenAI OCR

### workflows/ — business scenarios
- [`workflows/add-client-by-nip.md`](workflows/add-client-by-nip.md) — create a client from a Polish NIP using the Ministry of Finance Whitelist API

### scripts/ — shell wrappers
- `scripts/api.sh` — curl + Bearer + `/api/v1` prefix
- `scripts/login.sh` — device-code auth flow (opens browser, saves PAT to config)
- `scripts/pl-company-lookup.sh` — look up a Polish company by NIP via the Ministry of Finance Whitelist API

## General rules

**Auth**: JWT bearer token. If the API returns `401` the token is expired or invalid. Tell the user to re-run `login.sh`. Do not try to "fix" it on your own.

**URL prefix**: every endpoint lives under `/api/v1`. `api.sh` adds it for you — pass the path without the prefix.

**Identifiers**: UUID v4 everywhere. If you need an ID, look it up first via `GET` + search (`?search=...` or a dedicated `/search` endpoint). Do not invent IDs.

**Pagination**: default `perPage=20`, maximum depends on the module. Params: `page` (1-based), `perPage`, `search` — check the reference file for the specific module.

**Dates**: ISO 8601 with a timezone offset, e.g. `2026-04-16T12:00:00+02:00`. Always include the offset.

**Money / numbers**: `unitPrice`, `creditLimit`, etc. are numbers (not strings), in the base currency (PLN). VAT is a percentage (0, 5, 8, 23).

**Localization**: the API speaks English. UI strings are translated in `apps/web/messages` — you don't need to touch those.

**Idempotency**: POST is not idempotent. Before creating something (especially clients and suppliers), check that it doesn't exist yet (`/clients/search?q=<NIP>`). Otherwise you'll create duplicates.

**Cancel / delete**: DELETE is almost always a soft delete (sets `isActive=false` or `deletedAt`). Hard deletes go through the DBA — don't attempt them.

## Confirmations before writes

Before any mutating operation (POST/PUT/DELETE/PATCH), **always** show the user:
- what you are about to do (method + path)
- the request body
- a short summary in the user's language

Then wait for confirmation. Exception: when the user has explicitly said "go ahead, don't ask" in the current session.

## Setup (first run)

If `~/.freshfork/config` doesn't exist, **tell the user to run the login script** — they do not need to know anything about tokens:

```bash
bash "$SKILL_DIR/scripts/login.sh"
# or, if the URL is already known:
bash "$SKILL_DIR/scripts/login.sh" https://crm.similar.group
```

The script will:
1. Ask for the CRM URL once and remember it
2. Open `/settings/connect-cli?code=...` in the browser — the user is already logged into the web app
3. User clicks "Approve" → a Personal Access Token (PAT) is created, valid for 90 days
4. The script receives the token and writes `~/.freshfork/config` (chmod 600)

If anything goes sideways (401, "token expired/consumed") — tell the user to rerun `login.sh`.

**Important for Claude**: do not run `login.sh` automatically — it opens a browser and waits for a human. Give the user the command and ask them to run it in a terminal.

## Updating the skill

This skill is shipped as a Claude plugin. Plugins auto-check for updates from the Freshfork marketplace at every session start.

**Marketplace URL**: `https://gitlab.com/freshforkpublic/claude-skills.git`

To update manually:
- Claude Code CLI: `/plugin marketplace update freshfork`
- Cowork: Settings → Plugins → click the update icon next to `freshfork-crm`

Release history: see `CHANGELOG.md` at the plugin root.

---

**Plugin version**: see `.claude-plugin/plugin.json`.
