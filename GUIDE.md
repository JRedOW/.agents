# Guide

How to add and maintain shared assets across opencode, Claude Code, and future harnesses.

## Adding a skill

1. `mkdir -p ~/.agents/skills/<group>/my-skill` (group folder optional, e.g. `caveman`) and create `SKILL.md` inside it:

   ```
   ---
   name: my-skill
   description: What it does and when to trigger it. Front-load trigger keywords.
   ---
   ```

2. Run `~/.agents/scripts/link.sh` (creates the harness symlinks).
3. Restart opencode and Claude Code.

Rules: `name` is lowercase-hyphen, max 64 chars, must match the leaf folder name. `description` is required; skills without one are filtered out by opencode. Both tools scan one skill folder deep, so group folders are flattened by `link.sh` into per-item harness links; do not nest deeper than `skills/<group>/<name>/`.

## Adding an agent

Create `~/.agents/agents/my-agent.md` (group folder optional, e.g. `agents/caveman/`):

```
---
description: What this agent is for.
mode: subagent
---

Prompt body. The body is the system prompt in opencode and the subagent prompt in Claude Code.
```

Frontmatter compatibility rules:

- Keep the union of fields; both tools tolerate the other's fields. opencode routes unknown fields into `options`; Claude Code ignores them. Keeping `mode:`, `permission:`, `tools:` is fine.
- Do NOT set `model:`. opencode wants `provider/model-id`, Claude Code wants `sonnet`/`claude-*`. Set per-tool models instead:
  - opencode: `agent: { "my-agent": { "model": "..." } }` in `harnesses/opencode/opencode.json`.
  - Claude Code: its own settings.
- `description` is the one required field in both tools.

`mode: subagent` is ignored by Claude Code (all its agents are subagents). opencode primary agents use `mode: primary` or `mode: all`; Claude Code ignores those too.

## Adding a command

Create `~/.agents/commands/my-command.md` (group folder optional, e.g. `commands/caveman/`):

```
---
description: One sentence.
---

The prompt to run. $ARGUMENTS is replaced with the user's input; $1, $2, ... for positional args.
```

Keep frontmatter to `description` for portability. opencode extras (`agent:`, `model:`, `subtask:`) and Claude Code extras (`allowed-tools:`, `argument-hint:`, `model:`) are only safe if you accept the other tool ignoring them. Group folders change nothing for the tools: `link.sh` flattens items into each harness, so commands keep their top-level names (`/caveman`, not `/caveman/caveman`). Run `link.sh`, restart both tools. `link.sh` excludes paths via hierarchical `.ignore` files (gitignore-style syntax; a leading `[claude]` or `[opencode]` tag scopes a rule to one harness).

## Vendoring upstream dependencies

Third-party dependencies are tracked in [DEPENDENCIES.md](DEPENDENCIES.md), which also documents each one's per-harness install and update steps; `scripts/check-deps.sh` validates its version table. Read that file before touching anything vendored.

For suites vendored at hub level (e.g. caveman, mattpocock skills), the generic flow:

1. `scripts/sync-upstream.sh <name> <owner/repo>#v<version> [path mappings]` fetches the upstream repo at the tag and copies the mapped paths. Prefer explicit file mappings over directory copies so upstream moves surface as errors instead of silent drift.
2. Re-apply hub-local adaptations (e.g. agent frontmatter transforms) that upstream applies at its own install time.
3. Review `git status` / `git diff` before committing. `rsync --delete` modes also remove items deleted upstream. The script re-runs `scripts/link.sh`.
4. Restart opencode and Claude Code, then bump the version in the `DEPENDENCIES.md` table.

Per-harness installs that bypass the hub (npm plugins, Claude Code marketplace plugins, `uvx` servers) are updated in each harness's own config; see the per-dependency sections in DEPENDENCIES.md. The `.ignore` files prune shared hub items per harness when a plugin supplies its own copies (e.g. the caveman Claude Code plugin supplies the full suite, so `[claude]` rules in `skills/caveman/.ignore`, `commands/caveman/.ignore`, and `agents/caveman/.ignore` prune the hub links).

## Global instructions (AGENTS.md)

Edit `~/.agents/AGENTS.md`. Both tools read it through symlinks (opencode: `AGENTS.md`, Claude Code: `CLAUDE.md`). Keep content tool-agnostic; harness-specific instructions go in each harness's own config.

## MCP servers (ex. Context7)

MCP config is per-tool by design. Context7 is the running example; see [DEPENDENCIES.md](DEPENDENCIES.md) for the authoritative per-dependency details.

opencode (already configured in `harnesses/opencode/opencode.json`):

```
"mcp": {
  "context7": {
    "type": "remote",
    "url": "https://mcp.context7.com/mcp",
    "enabled": true
  }
}
```

Claude Code: context7 ships as a hub-local plugin. `harnesses/claude/marketplace/` is a tracked directory marketplace (`hub-mcp`) holding the `context7` plugin with its `.mcp.json` (remote server URL). It is registered in `harnesses/claude/settings.template.json` under `extraKnownMarketplaces.hub-mcp` and enabled via `enabledPlugins`. Marketplace edits load at restart or `/reload-plugins`; manage the server via `/mcp`. The marketplace `path` uses `~`, which Claude Code expands at startup, so the template stays username-portable; if the hub repo moves to a different directory (not just a different `$HOME`), update `extraKnownMarketplaces.hub-mcp.source.path` in both the template and the live `settings.json`.

## Harness-specific config

opencode lives in `harnesses/opencode/` (config, plugins). It reaches shared assets through per-item symlinks that `link.sh` generates and git tracks. Plugins come in two shapes: npm-installed (e.g. `@dietrichgebert/ponytail`, pinned in `opencode.json`'s `plugin` array and downloaded into `~/.cache/opencode/packages/` at startup) and real directories under `harnesses/opencode/plugins/` referenced as `./plugins/<name>` in `opencode.json` (e.g. caveman, synced by `sync-upstream.sh`). opencode auto-installs plugin deps at startup, generating `package.json`, `package-lock.json`, and `node_modules/`; all are gitignored and regenerate on launch.

Claude Code lives in `harnesses/claude/` (`settings.json` is tracked; sessions, caches, credentials, and other state are gitignored). It reaches shared assets two ways: the same per-item symlinks, and plugins installed from marketplaces declared in `settings.template.json` (`extraKnownMarketplaces` + `enabledPlugins`): ponytail and caveman from their GitHub marketplaces, context7 from the hub-local `hub-mcp` marketplace. `settings.template.json` is the tracked source; apply version bumps there and to the live `settings.json`.
