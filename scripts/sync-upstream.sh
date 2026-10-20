#!/bin/bash
# Sync vendored third-party assets into this hub from an upstream repo.
#
# Fetches the upstream source into a temp dir, rsyncs each asset type into
# the hub's per-source group dir (skills/NAME/, agents/NAME/, commands/NAME/),
# then refreshes harness symlinks via scripts/link.sh.
#
# usage: scripts/sync-upstream.sh NAME OWNER/REPO [options] [skills|agents|commands...]
#
# options:
#   --via skills   fetch skill-pack repos through `npx skills` instead of git
#                  clone (validates SKILL.md frontmatter and flattens grouped
#                  upstream layouts into one skill per dir)
#   --raw src:dst  extra mapping, dst is always a hub directory (repeatable):
#                  src dir  -> contents copied into dst (dst extras deleted)
#                  src file -> file copied into dst
#   --no-link      skip scripts/link.sh after syncing
#
# .ignore files are local-only: every rsync excludes them, so local ones
# survive --delete and upstream ones are never copied in.
#
# NAME must not contain slashes. If OWNER/REPO is a full git URL it is cloned
# verbatim, otherwise https://github.com/OWNER/REPO is used.
#
# examples:
#   scripts/sync-upstream.sh mattpocock mattpocock/skills --via skills skills
#   scripts/sync-upstream.sh suite LessiaBear/example --raw skills/x:skills/suite/x

set -euo pipefail

HUB="$(cd "$(dirname "$0")/.." && pwd)"

if [ "$#" -lt 2 ]; then
  sed -n '2,27p' "$0" >&2
  exit 1
fi

NAME="$1"
REPO="$2"
shift 2

if [[ "$NAME" == */* ]]; then
  echo "error: NAME must not contain slashes: '$NAME'" >&2
  exit 1
fi

VIA_SKILLS=0
NO_LINK=0
RAW_MAPPINGS=()
ASSETS=()

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
    skills|agents|commands)
      ASSETS+=("$1")
      shift
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      sed -n '2,27p' "$0" >&2
      exit 1
      ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [ "$VIA_SKILLS" -eq 1 ]; then
  echo "fetching skill pack $REPO via npx skills..."
  (cd "$TMP" && \
    DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx skills@latest add "$REPO" \
      --skill '*' --copy -a claude-code -y >"$TMP/npx-skills.log" 2>&1) \
  || { echo "error: npx skills add failed; log:" >&2; cat "$TMP/npx-skills.log" >&2; exit 1; }
  SRC="$TMP/.claude/skills"
else
  case "$REPO" in
    *://*|*@*:*/*) URL="$REPO" ;;
    *) URL="https://github.com/$REPO" ;;
  esac
  echo "fetching $URL..."
  git clone --depth 1 "$URL" "$TMP/repo" >/dev/null 2>&1
  SRC="$TMP/repo"
fi

if [ "${#ASSETS[@]}" -eq 0 ]; then
  for t in skills agents commands; do
    [ -d "$SRC/$t" ] && ASSETS+=("$t")
  done
  [ "${#ASSETS[@]}" -gt 0 ] || { echo "error: no skills/agents/commands dirs found upstream" >&2; exit 1; }
fi

for t in "${ASSETS[@]}"; do
  if [ "$VIA_SKILLS" -eq 1 ]; then
    # npx skills flattens the pack into temp/.claude/skills/<skill>/
    [ "$t" = "skills" ] || continue
    rsync -a --delete --exclude=.ignore "$SRC/" "$HUB/$t/$NAME/"
  else
    [ -d "$SRC/$t" ] || { echo "error: upstream has no $t/ dir" >&2; exit 1; }
    rsync -a --delete --exclude=.ignore "$SRC/$t/" "$HUB/$t/$NAME/"
  fi
  echo "synced $t/$NAME/ ($(find "$HUB/$t/$NAME" -type f | wc -l | tr -d ' ') files)"
done

for raw in "${RAW_MAPPINGS[@]:-}"; do
  [ -n "$raw" ] || continue
  case "$raw" in
    *:*) src="${raw%%:*}"; dst="${raw#*:}" ;;
    *) echo "error: --raw needs src:dst, got '$raw'" >&2; exit 1 ;;
  esac
  [ -e "$SRC/$src" ] || { echo "error: upstream path not found: $src" >&2; exit 1; }
  mkdir -p "$HUB/$dst"
  if [ -f "$SRC/$src" ]; then
    rsync -a --exclude=.ignore "$SRC/$src" "$HUB/$dst/"
  else
    rsync -a --delete --exclude=.ignore "$SRC/$src/" "$HUB/$dst/"
  fi
  echo "synced $dst/ (raw: $src)"
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

echo "done: $NAME synced from $REPO"
