# .agents

Personal cross-platform agent configuration: shared skills, agents, and commands for opencode, Claude Code, and other harnesses.

## Layout

```
~/.agents/
├── AGENTS.md                 Shared global instructions (opencode AGENTS.md, Claude CLAUDE.md)
├── skills/<name>/SKILL.md    Shared skills (Agent Skills spec)
├── agents/<name>.md          Shared subagents
├── commands/<name>.md        Shared slash commands
├── harnesses/opencode/       opencode-specific config (symlinked as ~/.config/opencode)
│   ├── opencode.json
│   ├── plugins/
│   ├── .gitignore            node_modules, package.json, package-lock.json, bun.lock
│   ├── agents -> ../../agents
│   ├── commands -> ../../commands
│   └── AGENTS.md -> ../AGENTS.md
├── harnesses/claude/         claude-specific config (symlinked as ~/.claude)
│   ├── settings.json
│   ├── .gitignore            sessions, caches, credentials, flags
│   ├── skills/               per-skill symlinks -> ../../../skills/<name>
│   ├── agents -> ../../agents
│   ├── commands -> ../../commands
│   └── CLAUDE.md -> ../AGENTS.md
└── scripts/link.sh           Idempotent symlink wiring
```

## How each tool finds things

| Asset    | opencode                                       | Claude Code                 |
| -------- | ---------------------------------------------- | --------------------------- |
| Skills   | `~/.agents/skills/` (native)                   | `harnesses/claude/skills/` per-skill links |
| Agents   | `harnesses/opencode/agents` -> hub             | `harnesses/claude/agents` -> hub |
| Commands | `harnesses/opencode/commands` -> hub           | `harnesses/claude/commands` -> hub |
| Context  | `harnesses/opencode/AGENTS.md` -> hub          | `harnesses/claude/CLAUDE.md` -> hub |
| Config   | `~/.config/opencode` -> `harnesses/opencode/`  | `~/.claude` -> `harnesses/claude/` |

Claude Code scans skills one level deep only; do not nest skills. Never symlink `~/.claude/skills` itself at the top level (Claude writes `.system/` files into it); `harnesses/claude/skills/` is a real directory holding one symlink per skill.

## Setup on a new machine

```
git clone https://github.com/JRedOW/.agents.git ~/.agents
~/.agents/scripts/link.sh
```

`link.sh` is idempotent, refuses to clobber real files, and prunes stale links pointing into the hub. Run it after adding skills, agents, or commands. Restart opencode and Claude Code afterward; config is not hot-reloaded.

## Ignored state

Root `.gitignore` holds OS junk only (`.DS_Store`, `*.bak`). Each harness ignores its own runtime state via a local `.gitignore`. opencode auto-installs plugin deps at startup, generating `package.json`, `package-lock.json`, and `node_modules/` in `harnesses/opencode/`; all are ignored and regenerable.
