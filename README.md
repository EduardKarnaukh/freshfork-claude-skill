# Freshfork Claude plugin marketplace

This is the **source of truth** for Claude plugins that Freshfork ships. The repository is published as a marketplace — users install plugins from it via Claude Code CLI or Cowork.

## Install for users

**Claude Code CLI:**
```
/plugin marketplace add https://gitlab.com/freshforkpublic/claude-skills.git
/plugin install freshfork-crm@freshfork
```

**Cowork:** Settings → Plugins → Add marketplace → paste the URL above → Install `freshfork-crm`.

## Layout

```
.
├── .claude-plugin/
│   └── marketplace.json                        # marketplace index (one entry per plugin)
├── plugins/
│   └── freshfork-crm/                          # the plugin (installed as `freshfork-crm@freshfork`)
│       ├── .claude-plugin/
│       │   └── plugin.json                     # plugin manifest — **bump version here on every release**
│       ├── skills/
│       │   └── freshfork-crm/
│       │       ├── SKILL.md                    # entry point the model reads
│       │       ├── reference/                  # per-module API reference (one file = one domain)
│       │       ├── workflows/                  # business scenarios
│       │       └── scripts/                    # shell wrappers Claude invokes (api.sh, login.sh, ...)
│       ├── CHANGELOG.md
│       └── README.md
└── README.md
```

## Release checklist

When shipping a new version of `freshfork-crm`:

1. Edit files under `plugins/freshfork-crm/...`
2. Bump `plugins/freshfork-crm/.claude-plugin/plugin.json` → `version`
3. Bump the same version in `.claude-plugin/marketplace.json` → `plugins[].version` (Claude compares both; must match the plugin manifest)
4. Add a line to `plugins/freshfork-crm/CHANGELOG.md`
5. `git commit -am "freshfork-crm@<version>"`
6. `git tag v<version>` (optional but recommended)
7. `git push && git push --tags`
8. Users pull the new version automatically at their next Claude session start

Claude expects a strict-matching version bump — if you edit files but don't touch `version`, existing users will not receive the change.
