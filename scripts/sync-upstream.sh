#!/bin/bash
# Sync vendored third-party assets into this hub from an upstream repo.
#
# Fetches the upstream source into a temp dir, rsyncs each asset type into
# the hub's per-source group dir (skills/NAME/, agents/NAME/, commands/NAME/),
# then refreshes harness symlinks via scripts/link.sh.
#
# usage: scripts/sync-upstream.sh NAME OWNER/REPO[#REF] [options] [types...]
#
# options:
#   --via skills   fetch skill-pack repos through `npx skills` instead of git
#                  clone (validates SKILL.md frontmatter and flattens grouped
#                  upstream layouts into one skill per dir). With #REF the
#                  source is pinned: cloned at REF first, then `npx skills`
#                  runs against the local clone.
#   --raw src:dst  extra mapping, dst is a hub path (repeatable):
#                  src dir  -> contents copied into dst dir (dst extras deleted)
#                  src file -> file copied into dst dir when dst ends in /
#                              or dst already is a directory, else dst is the
#                              exact file path (copy renames the file)
#   --no-link      skip scripts/link.sh after syncing
#
# Types: skills | agents | commands, each optionally followed by "=items"
# (comma-separated names exact for skills, with or without .md for
# agents/commands files). Only the listed items stay in the group dir;
# everything else is pruned. Local .ignore files survive every sync.
# Without "=items" the whole upstream dir syncs.
#
# NAME must not contain slashes. If OWNER/REPO is a full git URL it is cloned
# verbatim, otherwise https://github.com/OWNER/REPO is used. #REF (tag or
# branch) pins the fetch, so what lands in the hub stays reproducible until
# the ref is bumped.
#
# examples:
#   scripts/sync-upstream.sh mattpocock mattpocock/skills#v1.3.1 --via skills skills
#   scripts/sync-upstream.sh caveman JuliusBrussee/caveman#v4.0.1 \
#     skills=a,b agents=x.md --raw src/hooks/x.js:plugins/caveman/x.cjs
#   scripts/sync-upstream.sh suite LessiaBear/example --raw skills/x:skills/suite/x

set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -lt 2 ]; then
  sed -n '2,39p' "$0" >&2
  exit 1
fi

NAME="$1"
REPOSPEC="$2"
shift 2

if [[ "$NAME" == */* ]]; then
  echo "error: NAME must not contain slashes: '$NAME'" >&2
  exit 1
fi

REF=""
REPO="$REPOSPEC"
case "$REPOSPEC" in
  *"#"*)
    REF="${REPOSPEC##*#}"
    REPO="${REPOSPEC%%#*}"
    ;;
esac

VIA_SKILLS=0
NO_LINK=0
RAW_MAPPINGS=()
ASSETS=()
FILTERS=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --via)
      [ "$2" = "skills" ] || { echo "error: --via expects 'skills'" >&2; exit 1; }
      VIA_SKILLS=1
      shift 2
      ;;
    --via-skills)
      # tolerated alias
      VIA_SKILLS=1
      shift
      ;;
    --raw)
      [ "$#" -ge 2 ] || { echo "error: --raw needs src:dst" >&2; exit 1; }
      RAW_MAPPINGS+=("$2")
      shift
      shift
      ;;
    --no-link)
      NO_LINK=1
      shift
      ;;
    skills=*|agents=*|commands=*)
      list="${1#*=}"
      [ -n "$list" ] || { echo "error: empty item list in '$1'" >&2; exit 1; }
      ASSETS+=("${1%%=*}")
      FILTERS+=("$list")
      shift
      ;;
    skills|agents|commands)
      ASSETS+=("$1")
      FILTERS+=("")
      shift
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      sed -n '2,39p' "$0" >&2
      exit 1
      ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# prune_from_filter <group_dir> <comma-separated items>: remove every entry
# not named in the item list (basename, or basename without a trailing .md
# for agent/command files). .ignore survives: it is hub-local.
prune_from_filter() {
  local dir="$1" items="$2" entry base
  for entry in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$entry" ] || continue
    base="${entry##*/}"
    [ "$base" = ".ignore" ] && continue
    case ",$items," in
      *",$base,"*|*",${base%.md},"*) : ;;
      *) rm -rf "$entry" ;;
    esac
  done
}

# raw_dst_is_dir <dst>: dst names a hub directory — explicitly when it ends
# in /, or implicitly when the path already exists as a directory.
# Otherwise a --raw file src is written at that exact path (renamed).
raw_dst_is_dir() {
  case "$1" in
    */) return 0 ;;
  esac
  [ -d "$HUB/$1" ]
}

if [ "$VIA_SKILLS" -eq 1 ]; then
  if [ -n "$REF" ]; then
    echo "cloning $REPOSPEC (pinned)..."
    case "$REPO" in
      *://*|*@*:*/*|/*) URL="$REPO" ;;
      *) URL="https://github.com/$REPO" ;;
    esac
    git clone --depth 1 --branch "$REF" "$URL" "$TMP/repo" >/dev/null 2>&1 \
      || { echo "error: could not clone $URL at ref '$REF'" >&2; exit 1; }
    echo "fetching skills from local clone via npx skills..."
    (cd "$TMP" && \
      DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx skills@latest add "$TMP/repo" \
        --skill '*' --copy -a claude-code -y >"$TMP/npx-skills.log" 2>&1) \
    || { echo "error: npx skills add failed; log:" >&2; cat "$TMP/npx-skills.log" >&2; exit 1; }
    SRC="$TMP/.claude/skills"
  else
    echo "fetching skill pack $REPO via npx skills..."
    (cd "$TMP" && \
      DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx skills@latest add "$REPO" \
        --skill '*' --copy -a claude-code -y >"$TMP/npx-skills.log" 2>&1) \
    || { echo "error: npx skills add failed; log:" >&2; cat "$TMP/npx-skills.log" >&2; exit 1; }
    SRC="$TMP/.claude/skills"
  fi
else
  case "$REPO" in
    *://*|*@*:*/*|/*) URL="$REPO" ;;
    *) URL="https://github.com/$REPO" ;;
  esac
  if [ -n "$REF" ]; then
    echo "cloning $URL at ref '$REF'..."
    git clone --depth 1 --branch "$REF" "$URL" "$TMP/repo" >/dev/null 2>&1 \
      || { echo "error: could not clone $URL at ref '$REF'" >&2; exit 1; }
  else
    echo "fetching $URL..."
    git clone --depth 1 "$URL" "$TMP/repo" >/dev/null 2>&1
  fi
  SRC="$TMP/repo"
fi

if [ "${#ASSETS[@]}" -eq 0 ]; then
  for t in skills agents commands; do
    [ -d "$SRC/$t" ] && ASSETS+=("$t")
  done
  [ "${#ASSETS[@]}" -gt 0 ] || { echo "error: no skills/agents/commands dirs found upstream" >&2; exit 1; }
fi

i=0
for t in "${ASSETS[@]}"; do
  filter=""
  [ "$i" -lt "${#FILTERS[@]}" ] && filter="${FILTERS[i]}"
  if [ "$VIA_SKILLS" -eq 1 ]; then
    # npx skills flattens the pack into temp/.claude/skills/<skill>/
    [ "$t" = "skills" ] || continue
    rsync -a --delete --exclude=.ignore "$SRC/" "$HUB/$t/$NAME/"
  else
    [ -d "$SRC/$t" ] || { echo "error: upstream has no $t/ dir" >&2; exit 1; }
    rsync -a --delete --exclude=.ignore "$SRC/$t/" "$HUB/$t/$NAME/"
  fi
  if [ -n "$filter" ]; then
    prune_from_filter "$HUB/$t/$NAME" "$filter"
  fi
  echo "synced $t/$NAME/ ($(find "$HUB/$t/$NAME" -type f | wc -l | tr -d ' ') files)"
  i=$((i+1))
done

for raw in "${RAW_MAPPINGS[@]:-}"; do
  [ -n "$raw" ] || continue
  case "$raw" in
    *:*) src="${raw%%:*}"; dst="${raw#*:}" ;;
    *) echo "error: --raw needs src:dst, got '$raw'" >&2; exit 1 ;;
  esac
  [ -e "$SRC/$src" ] || { echo "error: upstream path not found: $src" >&2; exit 1; }
  if [ ! -f "$SRC/$src" ]; then
    mkdir -p "$HUB/$dst"
    rsync -a --delete --exclude=.ignore "$SRC/$src/" "$HUB/$dst/"
    echo "synced $dst/ (raw: $src)"
  elif raw_dst_is_dir "$dst"; then
    mkdir -p "$HUB/$dst"
    rsync -a --exclude=.ignore "$SRC/$src" "$HUB/$dst/"
    echo "synced $dst/ (raw: $src)"
  else
    mkdir -p "$HUB/$(dirname "$dst")"
    rsync -a --exclude=.ignore "$SRC/$src" "$HUB/$dst"
    echo "synced $dst (raw: $src)"
  fi
done

# Warn when one skill dir basename exists under more than one hub source
# group: link.sh links skills flat per harness, so colliding names would
# fight over the same harness links.
if [ "${#ASSETS[@]}" -gt 0 ] && [ -d "$HUB/skills" ]; then
  DUPLICATES=$(find "$HUB/skills" -mindepth 2 -maxdepth 2 -type d \
    | sed 's|.*/||' | sort | uniq -d)
  for dup in $DUPLICATES; do
    echo "warning: duplicate skill name '$dup' in multiple hub source groups:" >&2
    find "$HUB/skills" -mindepth 2 -maxdepth 2 -type d -name "$dup" >&2
  done
fi

if [ "$NO_LINK" -eq 0 ]; then
  "$HUB/scripts/link.sh"
fi

echo "done: $NAME synced from $REPOSPEC"
