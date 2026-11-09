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
#
# Profiles (declared in PROFILES.md) each get a full config dir at
# harnesses/<harness>/profiles/<name>/, built with that profile's <tag>
# rules active. Point CLAUDE_CONFIG_DIR or OPENCODE_CONFIG_DIR at it
# (scripts/profiles.sh defines launchers). The base dir never fires
# profile rules.

set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"
HARNESSES=(claude opencode)
TYPES=(agents commands skills)

LINKUP=0
SELECTED=()
PROFILE_SELECTED=()

usage() {
  cat >&2 <<EOF
usage: scripts/link.sh [--linkup] [--harness <name>] ...

  (no options)    wire everything: harness-level symlinks plus per-item links
  --linkup        per-item links and pruning only, skip harness-level symlinks
  --harness NAME  limit work to one harness (claude, opencode); repeatable

Profile dirs from PROFILES.md are always rebuilt for the selected harnesses.
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

# --- PROFILES.md ---------------------------------------------------------------
# Rows of the markdown table: | name | harness, harness | description |.
# A missing file means no profiles. Bad rows abort before anything is touched.
PROFILES=()
PROFILE_HARNESSES=()
if [ -f "$HUB/PROFILES.md" ]; then
  ln=0
  while IFS= read -r line || [ -n "$line" ]; do
    ln=$((ln+1))
    case "$line" in
      '|'*) ;;
      *) continue ;;
    esac
    IFS='|' read -r _ name hs _ <<< "$line"
    read -r name <<< "$name" || true
    if [ "$name" = "Profile" ] || [[ "$name" =~ ^:?-+:?$ ]]; then
      continue
    fi
    if ! [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: PROFILES.md:$ln bad profile name '$name'" >&2
      exit 1
    fi
    if [ "$name" = "default" ]; then
      echo "error: PROFILES.md:$ln 'default' is reserved for the base dir" >&2
      exit 1
    fi
    case " ${PROFILES[*]-} " in
      *" $name "*)
        echo "error: PROFILES.md:$ln duplicate profile '$name'" >&2
        exit 1
        ;;
    esac
    hs="${hs//,/ }"
    read -r -a hlist <<< "$hs" || true
    if [ "${#hlist[@]}" -eq 0 ]; then
      echo "error: PROFILES.md:$ln profile '$name' lists no harnesses" >&2
      exit 1
    fi
    for h in "${hlist[@]}"; do
      case " ${HARNESSES[*]} " in
        *" $h "*) ;;
        *)
          echo "error: PROFILES.md:$ln unknown harness '$h' (${HARNESSES[*]})" >&2
          exit 1
          ;;
      esac
    done
    PROFILES+=("$name")
    PROFILE_HARNESSES+=(" ${hlist[*]} ")
  done < "$HUB/PROFILES.md"
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
# rule: [harness,...] (claude, opencode) and <profile,...> (PROFILES.md
# names, plus "default" for the base dir). Tags may both appear on one
# line in either order; both must fire for the rule to apply, names
# inside a tag are OR. A rule with a profile tag only fires while
# building one of its profiles' dirs.

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
          case " ${PROFILES[*]-} default " in
            *" $name "*) ;;
            *)
              echo "WARN    $file:$ln2 unknown profile '$name' in tag, rule skipped" >&2
              ok=0
              ;;
          esac
        done
        # the base dir builds as the reserved profile "default"
        local fires=1 psel="${PROFILE_SELECTED[*]:-default}"
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

# up_path <rel-path>: one ".." per component, e.g. a/b/c -> ../../..
up_path() {
  printf '%s' "$1" | sed 's|[^/][^/]*|..|g'
}

# sync_assets <root> <type>: root is the hub-relative config dir
# (harnesses/<harness> or harnesses/<harness>/profiles/<name>)
sync_assets() {
  local root="$1" type="$2"
  local hub_dir="$HUB/$type"
  local out_dir="$HUB/$root/$type"
  [ -d "$hub_dir" ] || return 0
  mkdir -p "$out_dir"

  local seen src name leaf target ups
  ups="$(up_path "$root/$type")"
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
    # Link lives at $HUB/<root>/<type>/<name>: one level up per root/type component.
    link "$out_dir/$name" "$ups/$leaf"
  done < <(find_leaves "$type")
  rm -f "$seen"
}

# prune_stale <root>: drop dangling links into the hub under root's type dirs
prune_stale() {
  local root="$1" type dir entry target
  for type in "${TYPES[@]}"; do
    dir="$HUB/$root/$type"
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

# merge_json <base> <patch>: print base deep-merged with patch. Objects
# merge per key, arrays append items not already present (order kept),
# scalars take the patch value, and a null in the patch deletes the key.
merge_json() {
  jq -n --slurpfile b "$1" --slurpfile p "$2" '
    def merge($p):
      if ($p|type) == "object" and (type == "object" or . == null) then
        reduce ($p|to_entries[]) as $e (. // {};
          if $e.value == null then del(.[$e.key])
          else .[$e.key] |= merge($e.value) end)
      elif type == "array" and ($p|type) == "array" then
        reduce $p[] as $x (.; if index([$x]) then . else . + [$x] end)
      else $p end;
    $b[0] | merge($p[0])'
}

# seed_config <live> <base> [patch]: write a missing live config from base,
# deep-merged with patch when given. Never overwrites: live configs take
# machine-local and hand edits (Orca injects hooks into the base
# settings.json via ~/.claude), so they are gitignored.
seed_config() {
  local live="$1" base="$2" patch="${3-}" out
  if [ -e "$live" ]; then
    echo "skipped $live exists; template changes not applied"
    return 0
  fi
  [ -f "$base" ] || return 0
  if [ -z "$patch" ]; then
    cp "$base" "$live"
    echo "copied  $live <- ${base#"$HUB"/}"
  elif out="$(merge_json "$base" "$patch")"; then
    printf '%s\n' "$out" > "$live"
    echo "merged  $live <- ${base#"$HUB"/} + ${patch#"$HUB"/}"
  else
    echo "ERROR   could not merge ${patch#"$HUB"/} (needs jq and plain JSON)" >&2
    return 1
  fi
}

# Base harness files a profile dir links back to. A real file at the same
# path in the profile dir (e.g. an opencode.json seeded from a template)
# is kept.
profile_shared() {
  case "$1" in
    claude)   echo CLAUDE.md ;;
    opencode) printf '%s\n' AGENTS.md opencode.json plugins/caveman ;;
  esac
}

# build_root <harness> <root> [profile]: per-item links (plus pruning) for
# one config dir, with only the given profile's <tag> rules active
build_root() {
  local harness="$1" root="$2" type
  PROFILE_SELECTED=(${3+"$3"})
  load_rules "$harness"
  prune_stale "$root"
  for type in "${TYPES[@]}"; do
    sync_assets "$root" "$type"
  done
}

build_profile() {
  local harness="$1" name="$2"
  local root="harnesses/$harness/profiles/$name" path base patch
  mkdir -p "$HUB/$root"
  # profile *.template.json files are patches deep-merged onto the base
  case "$harness" in
    claude)
      patch="$HUB/$root/settings.template.json"
      [ -f "$patch" ] || patch=""
      seed_config "$HUB/$root/settings.json" "$HUB/harnesses/claude/settings.template.json" "$patch"
      ;;
    opencode)
      # without a template, the shared links below point at the base opencode.json
      patch="$HUB/$root/opencode.template.json"
      if [ -f "$patch" ]; then
        if [ -L "$HUB/$root/opencode.json" ]; then
          rm "$HUB/$root/opencode.json"
        fi
        seed_config "$HUB/$root/opencode.json" "$HUB/harnesses/opencode/opencode.json" "$patch"
      fi
      ;;
  esac
  while IFS= read -r path; do
    base="$HUB/harnesses/$harness/$path"
    [ -e "$base" ] || [ -L "$base" ] || continue
    if [ -e "$HUB/$root/$path" ] && [ ! -L "$HUB/$root/$path" ]; then
      echo "kept    $HUB/$root/$path (profile override)"
      continue
    fi
    link "$HUB/$root/$path" "$(up_path "$(dirname "profiles/$name/$path")")/$path"
  done < <(profile_shared "$harness")
  build_root "$harness" "$root" "$name"
}

# prune_profiles <harness>: unlink hub-owned links in profile dirs no longer
# declared for this harness. Runtime state (login, history) is left alone.
prune_profiles() {
  local harness="$1" dir name entry
  for dir in "$HUB/harnesses/$harness/profiles"/*/; do
    [ -d "$dir" ] || continue
    dir="${dir%/}"
    name="${dir##*/}"
    if profile_has "$name" "$harness"; then
      continue
    fi
    while IFS= read -r entry; do
      case "$(readlink "$entry")" in
        ../*)
          rm "$entry"
          echo "pruned  $entry (profile removed)"
          ;;
      esac
    done < <(find "$dir" -maxdepth 2 -type l)
    echo "WARN    $dir is no longer a $harness profile; delete it by hand" >&2
  done
}

# profile_has <profile> <harness>: 0 when PROFILES.md lists the harness
profile_has() {
  local i
  for i in ${PROFILES[@]+"${!PROFILES[@]}"}; do
    if [ "${PROFILES[$i]}" = "$1" ]; then
      case "${PROFILE_HARNESSES[$i]}" in
        *" $2 "*) return 0 ;;
      esac
    fi
  done
  return 1
}

for harness in "${SELECTED[@]}"; do
  if [ "$harness" = "claude" ]; then
    seed_config "$HUB/harnesses/claude/settings.json" "$HUB/harnesses/claude/settings.template.json"
  fi

  if [ "$LINKUP" -ne 1 ]; then
    # one harness-level symlink per selected harness
    link "$(ext_link_path "$harness")" "$HUB/harnesses/$harness"
  fi

  # per-item links for shared assets, base dir first, then each profile
  build_root "$harness" "harnesses/$harness"
  for name in ${PROFILES[@]+"${PROFILES[@]}"}; do
    if profile_has "$name" "$harness"; then
      build_profile "$harness" "$name"
    fi
  done
  prune_profiles "$harness"
done

echo "done"
