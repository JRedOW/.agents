# Dependencies

Third-party dependencies used by this repo. Each dependency lists hub-level info, then harness-specific sections. The harnesses themselves are tracked in [HARNESSES.md](HARNESSES.md). `scripts/check-deps.sh` parses this table: Local version must be a single semver plus its release source, `x.y.z (github owner/repo)` or `x.y.z (pypi package)`.


| Dependency                                                         | Repository                                                                               | Local version                                      |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- | -------------------------------------------------- |
| `@dietrichgebert/ponytail` (plugins)                               | [https://github.com/dietrichgebert/ponytail](https://github.com/dietrichgebert/ponytail) | 5.3.2 (github dietrichgebert/ponytail)             |
| caveman suite (vendored skills, agents, commands, opencode plugin) | [https://github.com/JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman)     | 4.0.1 (github JuliusBrussee/caveman)               |
| mattpocock skills suite (vendored skills)                          | [https://github.com/mattpocock/skills](https://github.com/mattpocock/skills)             | 1.3.1 (github mattpocock/skills)                   |
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

Vendored from `JuliusBrussee/caveman`, pinned to a release tag. The file lists mirror upstream's own installer (`installer/install.js`, `installer/lib/opencode-agent.js`): `OPENCODE_SKILL_DIRS`, `OPENCODE_AGENT_FILES`, `OPENCODE_COMMAND_FILES`, and the opencode plugin layout (the two `.cjs` helpers are renamed copies of `src/hooks/caveman-config.js` / `caveman-parse.js`).

Shared skills, agents, and commands reach both harnesses through the per-item symlinks created by `scripts/link.sh`.

To re-sync (hub level):

1. Bump the `#ref` in the command below to the wanted release tag, then run:

   ```
   scripts/sync-upstream.sh caveman JuliusBrussee/caveman#v<version> \
     skills=caveman,cavecrew,caveman-commit,caveman-compress,caveman-help,caveman-review,caveman-stats,megacave,ultracave \
     agents=cavecrew-builder,cavecrew-investigator,cavecrew-reviewer \
     --raw src/plugins/opencode/commands:commands/caveman \
     --raw src/plugins/opencode/package.json:harnesses/opencode/plugins/caveman/package.json \
     --raw src/plugins/opencode/plugin.js:harnesses/opencode/plugins/caveman/plugin.js \
     --raw src/plugins/opencode/server.js:harnesses/opencode/plugins/caveman/server.js \
     --raw src/hooks/caveman-config.js:harnesses/opencode/plugins/caveman/caveman-config.cjs \
     --raw src/hooks/caveman-parse.js:harnesses/opencode/plugins/caveman/caveman-parse.cjs
   ```

   Explicit plugin file mappings, so upstream moves surface as `upstream path not found` errors rather than silent drift.
2. Re-apply the hub-local agent adaptation. Upstream adds `mode: subagent` at opencode install time; the hub needs it in the vendored copy, one shared by both harnesses:

   ```
   for f in agents/caveman/cavecrew-*.md; do
     grep -q '^mode: subagent' "$f" || \
       perl -pi -e 'if (/^(name: .*)$/) { $_ = "$1\nmode: subagent\n" unless $c++ }' "$f"
   done
   ```

   This mirrors upstream's `transformOpencodeAgentFrontmatter`, which also strips `tools:` YAML arrays and provider-less `model:` values (opencode fails to resolve `model: haiku`; upstream 4.0.1 sets it on cavecrew-investigator and cavecrew-reviewer). Apply the full transform after the sync's `mode: subagent` step:

   ```
   for f in agents/caveman/cavecrew-*.md; do
     perl -ni -e 'print unless /^(tools[ \t]*: \[|model[ \t]*: (?!.*\/).*)$/' "$f"
   done
   ```
3. Review `git status` / `git diff` before committing. The script re-runs `scripts/link.sh`; restart opencode and Claude Code.
4. Update the version in this file's table (the release tag from step 1).

Note the plugin has known upstream issues referenced in `harnesses/opencode/plugins/caveman/plugin.js` (issues 418, 421); check whether fixes landed upstream before re-copying plugin files.

### opencode

The plugin dir `harnesses/opencode/plugins/caveman/` is a real directory referenced as `./plugins/caveman` in `opencode.json`; it is synced via the `--raw` mappings above, no separate update step.

### Claude Code

Not installed yet.

---

## mattpocock

Vendored from `mattpocock/skills`. Skills live flat in `skills/mattpocock/<skill>/`; upstream's `skills/engineering/` and `skills/productivity/` groups are flattened by the fetcher.

Shared skills reach both harnesses through the per-item symlinks created by `scripts/link.sh`. Upstream ships skills only; no agents or commands.

To update (hub level):

1. Bump the `#ref` in the command below to the wanted release tag, then run:
   `scripts/sync-upstream.sh mattpocock mattpocock/skills#v<version> --via skills skills`
   The `--via skills` mode fetches and validates through the official `npx skills` CLI (`npx skills add --skill '*' --copy` into a temp dir) instead of a plain clone. It requires Node >= 22.20. With `#ref`, the source is cloned at the tag first, then `npx skills` reads the local clone, so the fetch is reproducible.
2. Review `git status` / `git diff` before committing. The `rsync --delete` also removes skills deleted upstream.
3. The script re-runs `scripts/link.sh`; restart opencode and Claude Code.
4. Update the version in this file's table (latest release tag).

Note: `npx skills update` tracks only skills it installed itself (via its lockfiles), so it cannot drive these vendored copies; the re-sync command above is the update path.

### opencode

No per-harness files; covered by the hub-level `link.sh` links.

### Claude Code

No per-harness files; covered by the hub-level `link.sh` links.

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