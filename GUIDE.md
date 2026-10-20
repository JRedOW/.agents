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

## Global instructions (AGENTS.md)

Edit `~/.agents/AGENTS.md`. Both tools read it through symlinks (opencode: `AGENTS.md`, Claude Code: `CLAUDE.md`). Keep content tool-agnostic; harness-specific instructions go in each harness's own config.

## MCP servers (ex. Context7)

MCP config is per-tool by design; this repo documents the snippets to keep them in sync.

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

Claude Code (user scope, all projects):

```
claude mcp add -s user --transport http context7 https://mcp.context7.com/mcp
```

## Harness-specific config

opencode lives in `harnesses/opencode/` (config, plugins). It reaches shared assets through per-item symlinks that `link.sh` generates and git tracks. opencode auto-installs plugin deps at startup, generating `package.json`, `package-lock.json`, and `node_modules/` there; all are gitignored and regenerate on launch.

Claude Code lives in `harnesses/claude/` (`settings.json` is tracked; sessions, caches, credentials, and other state are gitignored). It reaches shared assets through the same per-item symlinks.
