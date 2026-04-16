# freshfork-crm (Claude plugin)

Claude plugin for working with Freshfork CRM through its REST API. Adds a skill with API reference and business workflows so Claude can drive the CRM (Polish B2B — NIP/REGON, orders, warehouse, integrations).

Users don't install this plugin directly — they add the Freshfork marketplace (see the repo-root `README.md`) and run `/plugin install freshfork-crm@freshfork`.

## Layout

```
freshfork-crm/
├── .claude-plugin/
│   └── plugin.json             # manifest — `version` must be bumped on every release
├── skills/
│   └── freshfork-crm/
│       ├── SKILL.md            # entry point: map, auth, general rules
│       ├── reference/          # per-module API reference (one file = one domain)
│       ├── workflows/          # business scenarios
│       └── scripts/            # shell wrappers Claude invokes
├── CHANGELOG.md
└── README.md
```

## Authoring rules

- **Keep files small and independent.** Claude always reads `SKILL.md`; the rest is pulled on demand. Do not bloat `SKILL.md` — put details in `reference/` and `workflows/`.
- **`${CLAUDE_PLUGIN_ROOT}`** — inside `SKILL.md` and workflow files, the plugin's installed path is available as this env var at runtime. Use it when invoking scripts:
  ```bash
  bash "${CLAUDE_PLUGIN_ROOT}/skills/freshfork-crm/scripts/api.sh" GET /clients
  ```
- **Every change = version bump.** Update `.claude-plugin/plugin.json` (`version`) AND `.claude-plugin/marketplace.json` at the repo root. Claude compares both; a mismatch or same-version update is silently ignored.
