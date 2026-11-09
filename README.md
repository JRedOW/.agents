# .agents

Personal cross-platform agent configuration: shared skills, agents, and commands for opencode, Claude Code, and other harnesses.

## Layout

```
~/.agents/
├── AGENTS.md                          Shared global instructions (opencode AGENTS.md, Claude CLAUDE.md)
├── DEPENDENCIES.md                    Third-party dependency inventory + update guides
├── HARNESSES.md                       Installed harness versions + update guides
├── PROFILES.md                        Profile table read by link.sh and scripts/profiles.sh
├── skills/[<group>]/<name>/SKILL.md   Shared skills (Agent Skills spec), grouped one level deep
├── agents/[<group>]/<name>.md         Shared subagents (group folder optional)
├── commands/[<group>]/<name>.md       Shared slash commands (group folder optional)
├── harnesses/opencode/                opencode-specific config (symlinked as ~/.config/opencode)
│   ├── opencode.json
│   ├── plugins/
│   ├── .gitignore                     node_modules, package.json, package-lock.json, bun.lock
│   ├── AGENTS.md -> ../../AGENTS.md
│   ├── {agents,commands,skills}/      real dirs, one symlink per leaf item
│   └── profiles/<name>/               profile config dir (OPENCODE_CONFIG_DIR)
├── harnesses/claude/                  claude-specific config (symlinked as ~/.claude)
│   ├── settings.json
│   ├── .gitignore                     sessions, caches, credentials, flags
│   ├── CLAUDE.md -> ../../AGENTS.md
│   ├── {agents,commands,skills}/      real dirs, one symlink per leaf item
│   └── profiles/<name>/               profile config dir (CLAUDE_CONFIG_DIR)
├── .ignore                            link.sh exclusions (gitignore-style)
├── scripts/link.sh                    Idempotent symlink wiring
└── scripts/profiles.sh                Shell launchers per profile (claude-<name>, opencode-<name>)
```

Hub assets may be grouped into folders one level deep (`skills/caveman/`, `agents/caveman/`). Harnesses stay flat: `link.sh` creates one symlink per leaf item, so tools never see the grouping. Exclusions are controlled by hierarchical `.ignore` files with gitignore-style syntax: the root `.ignore` covers the whole hub, and a `.ignore` in any subdirectory covers that directory and below. A leading `[claude]` or `[opencode]` tag scopes a rule to one harness; untagged rules apply to all. A leading `<blender>` tag scopes a rule to a profile, fired only while `link.sh` builds that profile's dir; the reserved `<default>` tag fires only in the base dir. A line may carry both tag kinds in either order, and both must match.

## Profiles

Profiles are declared in [PROFILES.md](PROFILES.md). For each listed harness, `link.sh` builds a full config dir at `harnesses/<harness>/profiles/<name>/`: per-item links (with the profile's `<name>` rules active), links back to the base `CLAUDE.md`/`AGENTS.md`, `opencode.json` and `plugins/caveman`, and a seeded config. A profile's `settings.template.json` (Claude) or `opencode.template.json` (opencode) holds only its differences; `link.sh` deep-merges it onto the base with `jq` and writes `settings.json` / `opencode.json` once, never overwriting (see [PROFILES.md](PROFILES.md)). Without a template, Claude copies the base template and opencode links the base `opencode.json`. The base dir never fires profile rules.

Use a profile by pointing the harness at its dir. `source ~/.agents/scripts/profiles.sh` in your shell rc defines one alias per profile and harness, e.g. `claude-blender` (`CLAUDE_CONFIG_DIR=…/harnesses/claude/profiles/blender claude`) and `opencode-blender` (`OPENCODE_CONFIG_DIR=…`). `CLAUDE_CONFIG_DIR` replaces `~/.claude` entirely, including login, history and `.claude.json`, so each Claude profile needs its own login. opencode 1.19 loads `OPENCODE_CONFIG_DIR` on top of `~/.config/opencode` (except `AGENTS.md`, which it replaces); v2 replaces the global dir. Orca hooks are not added to profiles.

## How each tool finds things

| Asset    | opencode                                              | Claude Code                  |
| -------- | ----------------------------------------------------- | ---------------------------- |
| Skills   | `harnesses/opencode/skills/` per-item links           | `harnesses/claude/skills/` per-item links |
| Agents   | `harnesses/opencode/agents/` per-item links           | `harnesses/claude/agents/` per-item links |
| Commands | `harnesses/opencode/commands/` per-item links         | `harnesses/claude/commands/` per-item links |
| Context  | `harnesses/opencode/AGENTS.md` -> `../../AGENTS.md`   | `harnesses/claude/CLAUDE.md` -> `../../AGENTS.md` |
| Config   | `~/.config/opencode` -> `harnesses/opencode/`         | `~/.claude` -> `harnesses/claude/` |

Never symlink a whole asset directory (`agents`, `commands`, `skills`) into a harness: nested hub groups would leak through. Claude Code namespaces commands inside subdirectories (`/group/cmd`), and opencode's `~/.config/opencode/skill(s)/*` scanner matches only one level deep, so a group link would hide the `SKILL.md` files below it. `skills/` must also be a real directory, because Claude Code writes `.system/` files into it. `link.sh` keeps every harness flat with one symlink per leaf item.

Discovery of grouped hub skills (`skills/<group>/<name>/SKILL.md`) differs per tool. opencode deep-scans `~/.agents/skills/**` as external skills, so it finds grouped hub skills natively even without links; that scan does not read hub `.ignore` rules, so excluded items (`megacave`, via `skills/caveman/.ignore`) still load in opencode. Claude Code has no equivalent hub scan, so the per-item `~/.claude/skills/` links remain its only hub discovery path. The links stay for both harnesses: they are where `.ignore` actually filters.

## Setup on a new machine

```
git clone https://github.com/JRedOW/.agents.git ~/.agents
~/.agents/scripts/link.sh
```

`link.sh` is idempotent, refuses to clobber real files, and prunes stale links pointing into the hub. Run it after cloning (required: harness links for all shared assets) and after adding skills, agents, or commands. Options: `--linkup` skips the harness-level symlinks (`~/.claude`, `~/.config/opencode`) and only does per-item links plus pruning; `--harness claude` or `--harness opencode` (repeatable, `all` allowed) limits work to selected harnesses, including their profile dirs. Restart opencode and Claude Code afterward; config is not hot-reloaded.

## Ignored state

Root `.gitignore` holds OS junk only (`.DS_Store`, `*.bak`). Each harness ignores its own runtime state via a local `.gitignore`. opencode auto-installs plugin deps at startup, generating `package.json`, `package-lock.json`, and `node_modules/` in `harnesses/opencode/`; all are ignored and regenerable.
