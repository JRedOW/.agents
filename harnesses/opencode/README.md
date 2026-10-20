# opencode config

Joseph's global opencode config, versioned. Powers agent behavior, slash commands, skills, plugins, and MCP servers across all projects.

## Style plugins

Two style plugins shape every session, and they are designed to pair: ponytail decides how much code gets written (lazy senior dev, smallest change), caveman decides how the reply reads (terse, compressed).

| Plugin | Version | Loaded via |
|--------|---------|------------|
| [ponytail](https://github.com/dietrichgebert/ponytail) (`@dietrichgebert/ponytail`) | 5.3.2 | `opencode.json` `plugin` entry |
| [caveman](https://github.com/JuliusBrussee/caveman) | 4.0.1 | `opencode.json` `plugin` entry (`./plugins/caveman`) + `Agents.md` ruleset |

## Updating caveman

Install/update pinned to a release tag (npm 12 needs `--allow-git=root`):

```sh
npx --allow-git=root -y github:JuliusBrussee/caveman#v4.0.1 -- --only opencode --force
```

Swap `v4.0.1` for the tag from https://github.com/JuliusBrussee/caveman/releases and after any opencode release change, `--force` backs up and replaces installer-owned files (`plugins/caveman/`, `commands/`, `skills/`, cavecrew agents), refreshes the caveman ruleset in `Agents.md`, and patches `opencode.json` to the newest entry format.

Notes:

- The installer refuses to overwrite untracked files it does not own; `--force` makes it back them up to `.caveman-opencode-backups/` instead. Ownership is tracked in `.caveman-opencode-ownership.json`.
- Run the same command with `--uninstall` to remove everything caveman owns here.
- Restart opencode after an update; plugins are read at session start.

## Updating ponytail

`opencode.json` pins the exact version in the `plugin` array (`@dietrichgebert/ponytail@5.3.2`). Check the latest release at https://github.com/dietrichgebert/ponytail/releases, then bump the pin:

```sh
npm view @dietrichgebert/ponytail version
```

Edit the version in `opencode.json`, then restart opencode.
