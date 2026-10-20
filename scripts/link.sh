#!/bin/bash
# Wire this repo's shared agents config into every harness.
# Idempotent: correct links are kept, wrong links are replaced.
# Refuses to touch real files or dirs. Prunes stale links into this repo.
#
# Hub assets may be grouped one level deep (agents/caveman/x.md,
# skills/caveman/<name>/SKILL.md). Harnesses stay flat: one symlink per
# leaf item. Folders starting with "." are ignored everywhere.

set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"
HARNESSES=(claude opencode)
TYPES=(agents commands skills)

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

# Leaf items: .md files for agents/commands, dirs holding SKILL.md for skills.
# Skips anything under a dot-folder or dotfile at any depth. Paths are printed
# relative to $HUB: "-not -path '*/.*'" only works on relative paths because
# $HUB itself (e.g. /Users/joseph/.agents) contains a dot component.
find_leaves() {
  local type="$1"
  case "$type" in
    skills)
      (cd "$HUB" && find "$type" -mindepth 2 -maxdepth 3 \
        -not -path '*/.*' -name 'SKILL.md' -type f) | sort
      ;;
    *)
      (cd "$HUB" && find "$type" -mindepth 1 -maxdepth 2 \
        -not -path '*/.*' -name '*.md' -type f) | sort
      ;;
  esac
}

sync_assets() {
  local harness="$1" type="$2"
  local hub_dir="$HUB/$type"
  local out_dir="$HUB/harnesses/$harness/$type"
  [ -d "$hub_dir" ] || return 0
  mkdir -p "$out_dir"

  local seen src name leaf
  seen="$(mktemp)"
  while IFS= read -r src; do
    case "$type" in
      skills)
        name="$(basename "$(dirname "$src")")"
        leaf="$(dirname "$src")" ;;
      *)
        name="$(basename "$src")"
        leaf="$src" ;;
    esac
    if grep -qx "$name" "$seen"; then
      echo "ERROR   duplicate item name '$name' under $hub_dir" >&2
      rm -f "$seen"
      return 1
    fi
    echo "$name" >> "$seen"
    # Link lives at $HUB/harnesses/<harness>/<type>/<name>: three levels up to $HUB.
    link "$out_dir/$name" "../../../$leaf"
  done < <(find_leaves "$type")
  rm -f "$seen"
}

prune_stale() {
  local harness type dir entry target
  for harness in "${HARNESSES[@]}"; do
    for type in "${TYPES[@]}"; do
      dir="$HUB/harnesses/$harness/$type"
      # Real dirs only; never descend through a symlink.
      [ -d "$dir" ] && [ ! -L "$dir" ] || continue
      while IFS= read -r entry; do
        target="$(readlink "$entry")"
        case "$target" in
          "$HUB"|"$HUB"/*|../*|..)
            if [ ! -e "$entry" ]; then
              rm "$entry"
              echo "pruned  $entry (stale)"
            fi
            ;;
        esac
      done < <(find "$dir" -maxdepth 1 -type l)
    done
  done
}

# opencode: one harness symlink
link "$HOME/.config/opencode" "$HUB/harnesses/opencode"

# claude code: one harness symlink
link "$HOME/.claude" "$HUB/harnesses/claude"

# prune stale per-item links inside each harness
prune_stale

# per-item links for shared assets in every harness
for harness in "${HARNESSES[@]}"; do
  for type in "${TYPES[@]}"; do
    sync_assets "$harness" "$type"
  done
done

echo "done"
