#!/bin/bash
# Wire this repo's shared agents config into every harness.
# Idempotent: correct links are kept, wrong links are replaced.
# Refuses to touch real files or dirs. Prunes stale links into this repo.
#
# Hub assets may be grouped at any depth (agents/caveman/x.md,
# skills/caveman/<name>/SKILL.md, skills/suite/<group>/<name>/SKILL.md).
# Harnesses stay flat: one symlink per leaf item. Hierarchical .ignore
# files (gitignore-style, with an optional [harness] tag) decide what is
# excluded.

set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"
HARNESSES=(claude opencode)
PROFILES=(blender)
TYPES=(agents commands skills)

LINKUP=0
SELECTED=()
PROFILE_SELECTED=()

usage() {
  cat >&2 <<EOF
usage: scripts/link.sh [--linkup] [--harness <name>] ... [--profile <name>] ...

  (no options)    wire everything: harness-level symlinks plus per-item links
  --linkup        per-item links and pruning only, skip harness-level symlinks
  --harness NAME  limit work to one harness (claude, opencode); repeatable
  --profile NAME  activate a profile (blender) so <name>-tagged .ignore
                  rules fire; repeatable
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --linkup)
      LINKUP=1
      ;;
    --harness)
      shift
      if [ "$#" -eq 0 ]; then
        echo "error: --harness needs a name" >&2
        usage
        exit 1
      fi
      case "$1" in
        all)
          if [ "${#SELECTED[@]}" -gt 0 ]; then
            echo "error: --harness all combined with specific harnesses" >&2
            exit 1
          fi
          ALL_REQUESTED=1
          ;;
        claude|opencode)
          if [ "${ALL_REQUESTED:-0}" -eq 1 ]; then
            echo "error: --harness all combined with specific harnesses" >&2
            exit 1
          fi
          SELECTED+=("$1")
          ;;
        *)
          echo "error: unknown harness '$1' (claude, opencode, or all)" >&2
          exit 1
          ;;
      esac
      ;;
    --profile)
      shift
      if [ "$#" -eq 0 ]; then
        echo "error: --profile needs a name" >&2
        usage
        exit 1
      fi
      case " ${PROFILES[*]} " in
        *" $1 "*) PROFILE_SELECTED+=("$1") ;;
        *)
          echo "error: unknown profile '$1' (${PROFILES[*]})" >&2
          exit 1
          ;;
      esac
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 1
      ;;
  esac
  shift
done

if [ "${ALL_REQUESTED:-0}" -eq 1 ] || [ "${#SELECTED[@]}" -eq 0 ]; then
  SELECTED=("${HARNESSES[@]}")
else
  SELECTED=($(printf '%s\n' "${SELECTED[@]}" | awk '!s[$0]++'))
fi
if [ "${#PROFILE_SELECTED[@]}" -gt 0 ]; then
  PROFILE_SELECTED=($(printf '%s\n' "${PROFILE_SELECTED[@]}" | awk '!s[$0]++'))
fi

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

# --- .ignore matching ---------------------------------------------------------
# Hierarchical, gitignore-style exclusion for leaf items. The hub root
# .ignore covers the whole hub; any .ignore under agents/commands/skills
# covers its own directory and below. Rules apply in file order and the
# last match wins, so ! re-includes. Unlike git, ! can also re-include
# paths under an excluded directory. Syntax: # comments, blank lines, *,
# ?, **, trailing / (dirs only), leading or inner / (anchored to the
# file's directory), ! negation, and optional leading tags scoping the
# rule: [harness,...] (claude, opencode) and <profile,...> (blender).
# Tags may both appear on one line in either order; both must fire for
# the rule to apply, names inside a tag are OR. A rule with a profile
# tag only fires when one of its profiles is selected via --profile.

# regex_escape_char <char>: print <char> as a literal in a POSIX ERE
regex_escape_char() {
  case "$1" in
    "\\")
      printf '\\\\'
      ;;
    .|'^'|'$'|'+'|'('|')'|'{'|'}'|'|'|'['|']')
      printf '\\%s' "$1"
      ;;
    *)
      printf '%s' "$1"
      ;;
  esac
}

# glob_to_ere <glob>: print the glob as a POSIX ERE (no anchors here).
# ** spans path components only in the gitignore positions: leading "**/",
# inner "/**/", trailing "/**"; elsewhere it degrades to ".*".
glob_to_ere() {
  local glob="$1" ere="" i=0 n=${#1} c
  while [ "$i" -lt "$n" ]; do
    c="${glob:i:1}"
    if [ "$c" = '*' ]; then
      if [ "${glob:i:2}" = '**' ]; then
        if [ "$i" -eq 0 ] && [ "${glob:i:3}" = '**/' ]; then
          ere+='(.*/)?'
          i=$((i+3))
          continue
        fi
        ere+='.*'
        i=$((i+2))
        continue
      fi
      ere+='[^/]*'
    elif [ "$c" = '?' ]; then
      ere+='[^/]'
    elif [ "$c" = '/' ] && [ "${glob:i:4}" = '/**/' ]; then
      ere+='(/.*)?/'
      i=$((i+4))
      continue
    elif [ "$c" = '/' ] && [ "${glob:i:3}" = '/**' ] && [ $((i+3)) -eq "$n" ]; then
      ere+='/.*'
      i=$((i+3))
      continue
    else
      ere+="$(regex_escape_char "$c")"
    fi
    i=$((i+1))
  done
  printf '%s' "$ere"
}

# parse_rule <base> <pattern>: append one rule to the RULE_* arrays.
# base is the directory of the .ignore file, "" for the hub root.
parse_rule() {
  local base="$1" pat="$2" negate=0 dironly=0 anchored=0 ere
  if [ -z "$pat" ]; then
    return 0
  fi
  if [ "${pat#!}" != "$pat" ]; then
    negate=1
    pat="${pat#!}"
  fi
  if [ "${pat%/}" != "$pat" ]; then
    dironly=1
    pat="${pat%/}"
  fi
  if [ -z "$pat" ]; then
    return 0
  fi
  if [ "${pat#/}" != "$pat" ]; then
    anchored=1
    pat="${pat#/}"
  fi
  case "$pat" in
    */*) anchored=1 ;;
  esac
  if [ -z "$pat" ]; then
    return 0
  fi
  # anchored ERE so matching is whole-path / whole-component, never substring
  ere="^($(glob_to_ere "$pat"))\$"
  RULE_BASE+=("$base")
  RULE_ERE+=("$ere")
  RULE_NEGATE+=("$negate")
  RULE_DIRONLY+=("$dironly")
  RULE_ANCHORED+=("$anchored")
}

# load_ignore_file <base> <harness> <file>: parse one .ignore into the
# RULE_* arrays. Rules tagged for other harnesses or inactive profiles
# are dropped; unknown names in a tag warn and skip the rule.
load_ignore_file() {
  local base="$1" harness="$2" file="$3"
  local line ok ln=0 ln2
  local -a tag_names
  local TAG_RE='^([\[<])([A-Za-z0-9._-]+(,[A-Za-z0-9._-]+)*)[]\>][[:space:]]*(.*)$'
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln+1))
    line="${line%$'\r'}"
    case "$line" in
      ''|'#'*) continue ;;
    esac
    # leading tags (either order, harness [] and profile <>) are ANDed
    while [[ "$line" =~ $TAG_RE ]]; do
      ln2="$ln"
      ok=1
      IFS=',' read -r -a tag_names <<< "${BASH_REMATCH[2]}"
      if [ "${BASH_REMATCH[1]}" = '[' ]; then
        for name in "${tag_names[@]}"; do
          case " ${HARNESSES[*]} " in
            *" $name "*) ;;
            *)
              echo "WARN    $file:$ln2 unknown harness '$name' in tag, rule skipped" >&2
              ok=0
              ;;
          esac
        done
        case " ${tag_names[*]} " in
          *" $harness "*) ;;
          *) continue 2 ;;
        esac
      else
        for name in "${tag_names[@]}"; do
          case " ${PROFILES[*]} " in
            *" $name "*) ;;
            *)
              echo "WARN    $file:$ln2 unknown profile '$name' in tag, rule skipped" >&2
              ok=0
              ;;
          esac
        done
        local fires=1 psel="${PROFILE_SELECTED[*]-}"
        for name in "${tag_names[@]}"; do
          case " $psel " in
            *" $name "*) fires=0 ;;
          esac
        done
        [ "$fires" -eq 1 ] && continue 2
      fi
      if [ "$ok" -ne 1 ]; then
        continue 2
      fi
      line="${BASH_REMATCH[4]}"
    done
    parse_rule "$base" "$line"
  done < "$file"
}

# load_rules <harness>: read the hub root .ignore plus every .ignore under
# the shared asset dirs. Root loads first; find | sort keeps each directory
# ahead of its subdirectories so deeper rules override shallower ones.
load_rules() {
  local harness="$1" t f
  RULE_BASE=()
  RULE_ERE=()
  RULE_NEGATE=()
  RULE_DIRONLY=()
  RULE_ANCHORED=()
  if [ -f "$HUB/.ignore" ]; then
    load_ignore_file "" "$harness" "$HUB/.ignore"
  fi
  for t in "${TYPES[@]}"; do
    [ -d "$HUB/$t" ] || continue
    while IFS= read -r f; do
      load_ignore_file "${f%/.ignore}" "$harness" "$HUB/$f"
    done < <(cd "$HUB" && find "$t" -name .ignore -type f | sort)
  done
}

# rule_matches <index> <rel-path>: 0 when rule idx matches the path or one
# of its ancestor dirs. rel-path is hub-root relative.
rule_matches() {
  local idx="$1" path="$2"
  local base="${RULE_BASE[$idx]}" ere="${RULE_ERE[$idx]}"
  local dironly="${RULE_DIRONLY[$idx]}" anchored="${RULE_ANCHORED[$idx]}"
  local rel="$path" p comp
  if [ -n "$base" ]; then
    case "$path" in
      "$base"/?*) rel="${path#"$base"/}" ;;
      *) return 1 ;;
    esac
  fi
  p="$rel"
  if [ "$anchored" -eq 1 ]; then
    while [ -n "$p" ]; do
      # a dir-only rule may match an ancestor dir, never the leaf file
      if [ "$dironly" -eq 0 ] || [ "$p" != "$rel" ]; then
        if [[ "$p" =~ $ere ]]; then
          return 0
        fi
      fi
      case "$p" in
        */*) p="${p%/*}" ;;
        *) p="" ;;
      esac
    done
    return 1
  fi
  while [ -n "$p" ]; do
    comp="${p%%/*}"
    case "$p" in
      */*)
        if [[ "$comp" =~ $ere ]]; then
          return 0
        fi
        p="${p#*/}"
        ;;
      *)
        if [ "$dironly" -eq 0 ] && [[ "$comp" =~ $ere ]]; then
          return 0
        fi
        p=""
        ;;
    esac
  done
  return 1
}

# is_ignored <rel-path>: exit 0 when the path must not be linked
is_ignored() {
  local path="$1" ignored=0 i
  if [ "${#RULE_ERE[@]}" -gt 0 ]; then
    for i in "${!RULE_ERE[@]}"; do
      if rule_matches "$i" "$path"; then
        if [ "${RULE_NEGATE[$i]}" -eq 1 ]; then
          ignored=0
        else
          ignored=1
        fi
      fi
    done
  fi
  if [ "$ignored" -eq 1 ]; then
    return 0
  fi
  return 1
}

# Leaf items: .md files for agents/commands, dirs holding SKILL.md for skills.
# Leaves may sit at any depth: skills/NAME/<name>/SKILL.md,
# skills/SOURCE/<group>/<name>/SKILL.md, agents/SOURCE/file.md,
# agents/SOURCE/<name>/nested.md. Deeper unnamed helper files inside item dirs
# are indexables false positives; use .ignore rules to opt them out. Exclusions
# are decided by is_ignored against the loaded .ignore rules.
find_leaves() {
  local type="$1"
  case "$type" in
    skills)
      (cd "$HUB" && find "$type" -mindepth 2 \
        -name 'SKILL.md' -type f) | sort
      ;;
    *)
      (cd "$HUB" && find "$type" -mindepth 1 \
        -name '*.md' -type f) | sort
      ;;
  esac
}

sync_assets() {
  local harness="$1" type="$2"
  local hub_dir="$HUB/$type"
  local out_dir="$HUB/harnesses/$harness/$type"
  [ -d "$hub_dir" ] || return 0
  mkdir -p "$out_dir"

  local seen src name leaf target
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
    if is_ignored "$src"; then
      # only prune links we own (relative targets into the hub)
      if [ -L "$out_dir/$name" ]; then
        target="$(readlink "$out_dir/$name")"
        case "$target" in
          ../*)
            rm "$out_dir/$name"
            echo "pruned  $out_dir/$name (ignored)"
            ;;
        esac
      fi
      continue
    fi
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
  local harness="$1" type dir entry target
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
}

ext_link_path() {
  case "$1" in
    claude)   echo "$HOME/.claude" ;;
    opencode) echo "$HOME/.config/opencode" ;;
  esac
}

for harness in "${SELECTED[@]}"; do
  load_rules "$harness"

  if [ "$harness" = "claude" ]; then
    # Restore live settings from the tracked template (settings.json is
    # gitignored: Orca injects machine-local hooks into it via ~/.claude).
    local_settings="$HUB/harnesses/claude/settings.json"
    if [ ! -e "$local_settings" ] && [ -f "$HUB/harnesses/claude/settings.template.json" ]; then
      cp "$HUB/harnesses/claude/settings.template.json" "$local_settings"
      echo "copied  $local_settings <- settings.template.json"
    fi
  fi

  if [ "$LINKUP" -ne 1 ]; then
    # one harness-level symlink per selected harness
    link "$(ext_link_path "$harness")" "$HUB/harnesses/$harness"
  fi

  prune_stale "$harness"

  # per-item links for shared assets
  for type in "${TYPES[@]}"; do
    sync_assets "$harness" "$type"
  done
done

echo "done"
