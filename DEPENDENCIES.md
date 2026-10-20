# Dependencies

Third-party dependencies used by this repo. Each dependency lists hub-level info, then harness-specific sections. The harnesses themselves are tracked in [HARNESSES.md](HARNESSES.md). `scripts/check-deps.sh` parses this table: Local version must be a single semver plus its release source, `x.y.z (github owner/repo)` or `x.y.z (pypi package)`.


| Dependency                                                         | Repository                                                                               | Local version                                      |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `@dietrichgebert/ponytail` (opencode plugin)                       | [https://github.com/dietrichgebert/ponytail](https://github.com/dietrichgebert/ponytail) | 5.3.2 (github dietrichgebert/ponytail)             |
| caveman suite (vendored skills, agents, commands, opencode plugin) | [https://github.com/JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)     | 4.0.1 (github JuliusBrussee/caveman)               |
| `mcp-for-blender` (MCP server, via `uvx`, formerly `blender-mcp`)  | [https://github.com/ahujasid/mcp-for-blender](https://github.com/ahujasid/mcp-for-blender) | 2.2.2 (pypi mcp-for-blender)                       |
| `context7` (remote MCP server)                                     | [https://github.com/upstash/context7](https://github.com/upstash/context7)               | hosted at `https://mcp.context7.com/mcp`, unpinned |


---

## Ponytail

### opencode

Pinned version string in `harnesses/opencode/opencode.json` (`plugin` array). opencode downloads the package at startup into `~/.cache/opencode/packages/`; `node_modules/`, `package.json`, and lockfile in `harnesses/opencode/` are generated and gitignored.

To update:

1. Bump the version in `opencode.json`, e.g. `@dietrichgebert/ponytail@x.y.z` to the wanted tag.
2. Restart opencode. It fetches the new version on launch.
3. Verify the cache directory `~/.cache/opencode/packages/@dietrichgebert/` contains the new version.
4. Update the version in this file's table.

### Claude Code

Not installed yet.

---

## Caveman

Vendored from `JuliusBrussee/caveman`. Files live in `skills/caveman/`, `agents/caveman/`, `commands/caveman/`, etc.

Shared skills, agents, and commands reach both harnesses through the per-item symlinks created by `scripts/link.sh`.

To re-sync (hub level):

1. Clone upstream into a scratch dir: `git clone https://github.com/JuliusBrussee/caveman /tmp/caveman-src`
2. Diff each vendored area against upstream equivalents (`skills/`, `agents/`, `commands/`, plugin sources) and inspect local-only changes before overwriting anything.
3. Re-copy changed files, preserving any local modifications you want to keep.
4. Run `~/.agents/scripts/link.sh` to refresh harness symlinks.
5. Restart opencode and Claude Code.
6. Update the version note in this file's table if upstream marked a release.

### opencode

Only the plugin differs from the hub: `harnesses/opencode/plugins/caveman/` is a real directory referenced as `./plugins/caveman` in `opencode.json`. It is part of the same re-sync flow above; no separate update step.

Note the plugin has known upstream issues referenced in `harnesses/opencode/plugins/caveman/plugin.js` (issues 418, 421); check whether fixes landed upstream before re-copying plugin files.

### Claude Code

Not installed yet.

---

## mcp-for-blender

Currently only in opencode, each harness requires a unique `BLENDER_PORT`.

Local MCP server, formerly `blender-mcp`. Requires `uv`/`uvx` on PATH. Bare `uvx mcp-for-blender` starts the server directly. 

Runs with `BLENDER_MCP_SAFE_MODE=1` set via the `environment` block, which enables the upstream tool-call validator.

### opencode

Configured as above in `opencode.json`.

To update:

1. Check the latest release on PyPI or the upstream repository (`mcp-for-blender`).
2. Bump the `uvx mcp-for-blender@<version>` string in `opencode.json`.
3. Restart opencode; uvx fetches the pinned version on first launch.

---

## context7

Remote MCP server; nothing is installed locally. Hosted at `https://mcp.context7.com/mcp`, unpinned.

### opencode

Configured in `opencode.json` under `mcp`.

To update: nothing to do. The server updates upstream. Keep config in `opencode.json` current if context7 changes its URL or API.

### Claude Code

Not installed yet.