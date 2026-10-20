#!/bin/bash
# Wire this repo's shared agents config into every harness.
# Idempotent: correct links are kept, wrong links are replaced.
# Refuses to touch real files or dirs. Prunes stale links into this repo.

set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"

link() {
  local link_path="$1" target="$2"
  if [ -L "$link_path" ]; then
    if [ "$(readlink "$link_path")" = "$target" ]; then
      echo "ok      $link_path"
      return 0
    fi
    ln -sfn "$target" "$link_path"
    echo "linked  $link_path -> $target (replaced)"
  elif [ -e "$link_path" ]; then
    echo "BLOCKED $link_path exists and is not a symlink; resolve manually" >&2
    return 1
  else
    mkdir -p "$(dirname "$link_path")"
    ln -s "$target" "$link_path"
    echo "linked  $link_path -> $target"
  fi
}

prune_skills() {
  local dir="$HUB/harnesses/claude/skills" entry target
  [ -d "$dir" ] || return 0
  while IFS= read -r entry; do
    target="$(readlink "$entry")"
    case "$target" in
      "$HUB"|"$HUB"/*)
        if [ ! -e "$entry" ]; then
          rm "$entry"
          echo "pruned  $entry (stale)"
        fi
        ;;
    esac
  done < <(find "$dir" -maxdepth 1 -type l)
}

# opencode: one harness symlink
link "$HOME/.config/opencode" "$HUB/harnesses/opencode"

# claude code: one harness symlink
link "$HOME/.claude" "$HUB/harnesses/claude"

# prune stale per-skill links inside the claude harness
prune_skills

echo "done"
