# Profiles

Profiles are alternate harness config dirs, used by pointing `CLAUDE_CONFIG_DIR` or `OPENCODE_CONFIG_DIR` at them. `scripts/link.sh` reads the table below and builds `harnesses/<harness>/profiles/<profile>/` for each listed harness. That dir is a full config: the base items plus the items that `<profile>`-tagged `.ignore` rules let through.

| Profile | Harnesses | Description |
|---|---|---|
| blender | claude, opencode | Blender MCP plugin, blender agent, and blender skill |

- **Profile**: the name used in `<name>` tags in `.ignore` files and in the launcher names (`claude-blender`). `default` is reserved: `<default>` rules fire only in the base dir.
- **Harnesses**: comma-separated. Valid names: `claude`, `opencode`.
- **Description**: notes only; `link.sh` ignores it.

## Adding a profile

1. Add a row above.
2. Tag the `.ignore` rules that should only fire for it, e.g. `<name> !*`.
3. Optional config patches, committed inside the profile dir. Each holds only what differs from the base and is deep-merged onto it with `jq`: objects merge per key, arrays gain the new items, scalars are replaced, and `null` deletes a key. Both files must be plain JSON (no comments).
   - Claude: `harnesses/claude/profiles/<name>/settings.template.json`, merged onto the base `settings.template.json`. Without it, the profile copies the base template.
   - opencode: `harnesses/opencode/profiles/<name>/opencode.template.json`, merged onto the base `opencode.json`. Without it, the profile links the base `opencode.json`.

   The merged `settings.json` / `opencode.json` is written once and never overwritten, so live edits survive. To pick up base or template changes, delete the generated file and rerun `link.sh`.
4. Run `scripts/link.sh`, then open a new shell so `scripts/profiles.sh` defines the launchers.

Each Claude profile has its own login, history, and `.claude.json`, so log in once per profile. Removing a row unlinks the profile's hub links but keeps the dir; delete it by hand.
