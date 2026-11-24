# Harnesses

The agent harnesses this repo configures. Third-party plugins and MCP servers are listed in [DEPENDENCIES.md](DEPENDENCIES.md).

 `scripts/check-deps.sh` parses this table like DEPENDENCIES.md: Local version must be a single semver plus its release source, `x.y.z (github owner/repo)`. `scripts/install-harnesses.sh` installs or updates to these pins with the official curl installers; it asks before replacing a curl install, and only reports a mismatch for other installs (brew, npm).

| Harness | Repository | Local version |
|---|---|---|
| opencode | https://github.com/sst/opencode | 1.19.6 (github sst/opencode) |
| Claude Code | https://github.com/anthropics/claude-code | 2.1.331 (github anthropics/claude-code) |

To update:

1. Bump the version in the table above.
2. Run `scripts/install-harnesses.sh`.
