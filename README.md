# .agents

Personal cross-platform agent configuration: shared skills, agents, and commands for opencode, Claude Code, and other harnesses.

## Layout

```
~/.agents/
├── AGENTS.md                          Shared global instructions (opencode AGENTS.md, Claude CLAUDE.md)
├── DEPENDENCIES.md                    Third-party dependency inventory + update guides
├── HARNESSES.md                       Installed harness versions + update guides
├── skills/<group>/<name>/SKILL.md     Shared skills (Agent Skills spec), grouped one level deep
├── agents/[<group>/]<name>.md         Shared subagents (group folder optional)
├── commands/[<group>/]<name>.md       Shared slash commands (group folder optional)
├── harnesses/opencode/                opencode-specific config (symlinked as ~/.config/opencode)
│   ├── opencode.json
│   ├── plugins/
│   ├── .gitignore                     node_modules, package.json, package-lock.json, bun.lock
│   ├── AGENTS.md -> ../../AGENTS.md
│   └── {agents,commands,skills}/      real dirs, one symlink per leaf item
├── harnesses/claude/                  claude-specific config (symlinked as ~/.claude)
│   ├── settings.json
│   ├── .gitignore                     sessions, caches, credentials, flags
│   ├── CLAUDE.md -> ../../AGENTS.md
│   └── {agents,commands,skills}/      real dirs, one symlink per leaf item
├── .ignore                            link.sh exclusions (gitignore-style)
└── scripts/link.sh                    Idempotent symlink wiring
```

Hub assets may be grouped into folders one level deep (`skills/caveman/`, `agents/caveman/`). Harnesses stay flat: `link.sh` creates one symlink per leaf item, so tools never see the grouping. Exclusions are controlled by hierarchical `.ignore` files with gitignore-style syntax: the root `.ignore` covers the whole hub, and a `.ignore` in any subdirectory covers that directory and below. A leading `[claude]` or `[opencode]` tag scopes a rule to one harness; untagged rules apply to all.

## How each tool finds things

| Asset    | opencode                                              | Claude Code                  |
| -------- | ----------------------------------------------------- | ---------------------------- |
| Skills   | `harnesses/opencode/skills/` per-item links           | `harnesses/claude/skills/` per-item links |
| Agents   | `harnesses/opencode/agents/` per-item links           | `harnesses/claude/agents/` per-item links |
| Commands | `harnesses/opencode/commands/` per-item links         | `harnesses/claude/commands/` per-item links |
| Context  | `harnesses/opencode/AGENTS.md` -> `../../AGENTS.md`   | `harnesses/claude/CLAUDE.md` -> `../../AGENTS.md` |
| Config   | `~/.config/opencode` -> `harnesses/opencode/`         | `~/.claude` -> `harnesses/claude/` |

Never symlink a whole asset directory (`agents`, `commands`, `skills`) into a harness: nested hub groups would leak through. Claude Code namespaces commands inside subdirectories (`/group/cmd`), and opencode's scanners only match one level deep. `skills/` must also be a real directory, because Claude Code writes `.system/` files into it. `link.sh` keeps every harness flat with one symlink per leaf item.

`link.sh` is required, not optional: once hub skills are grouped (`skills/<group>/<name>/SKILL.md`), no tool discovers them natively (native globs like `~/.agents/skills/*/SKILL.md` and `~/.config/opencode/skills/*/SKILL.md` only match one level). The per-item harness links are the only path that works for both tools.

## Setup on a new machine

```
git clone https://github.com/JRedOW/.agents.git ~/.agents
~/.agents/scripts/link.sh
```

`link.sh` is idempotent, refuses to clobber real files, and prunes stale links pointing into the hub. Run it after cloning (required: harness links for all shared assets) and after adding skills, agents, or commands. Options: `--linkup` skips the harness-level symlinks (`~/.claude`, `~/.config/opencode`) and only does per-item links plus pruning; `--harness claude` or `--harness opencode` (repeatable, `all` allowed) limits work to selected harnesses. Restart opencode and Claude Code afterward; config is not hot-reloaded.

## Ignored state

Root `.gitignore` holds OS junk only (`.DS_Store`, `*.bak`). Each harness ignores its own runtime state via a local `.gitignore`. opencode auto-installs plugin deps at startup, generating `package.json`, `package-lock.json`, and `node_modules/` in `harnesses/opencode/`; all are ignored and regenerable.
