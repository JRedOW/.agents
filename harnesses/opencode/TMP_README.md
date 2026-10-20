# opencode config

Joseph's global opencode config, versioned. Powers agent behavior, slash commands, skills, plugins, and MCP servers across all projects.

## Layout

| Path | Source |
|------|--------|
| `opencode.json` | Main config: permissions, LiteLLM provider, plugins, MCP (context7, blender-mcp) |
| `opencode.jsonc.bak` | Backup of a minimal config, unused |
| `Agents.md` | Agent instructions: communication style, subagent usage, tool policy |
| `agents/*.md` | Subagents: cavecrew-builder/investigator/reviewer, Blender assistant |
| `commands/*.md` | Slash commands: `/caveman*` suite |
| `skills/*/SKILL.md` | Skills: caveman suite, cavecrew. `caveman-compress/scripts/` holds the Python compression CLI |
| `plugins/caveman/` | Local plugin: session mode flag, `/caveman` parsing, config/parse helpers |
| `package.json` | Deps: `@opencode-ai/plugin` (node_modules is install target, gitignored) |

## External dependencies

- `@dietrichgebert/ponytail`, loaded via `opencode.json` plugins
- `@dietrichgebert/ponytail` skill bundle at `~/.cache/opencode/packages/`
