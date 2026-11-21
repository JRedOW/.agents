#!/usr/bin/env bash
# install-harnesses.sh — install or update the harnesses pinned in HARNESSES.md
# with the official curl installers.
#
# Per harness:
#   not installed                -> install the pinned version
#   installed, matches the pin   -> nothing
#   differs, curl-installed      -> ask before installing the pinned version
#   differs, other install (brew, npm, ...) -> tell the user to update it
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESSES="$ROOT/HARNESSES.md"

# <name> -> binary, curl install command, curl install dir (resolved path prefix)
spec() {  # <row name> <version>; sets BIN INSTALL CURL_DIRS or returns 1
  case "$1" in
    opencode)
      BIN=opencode
      INSTALL="curl -fsSL https://opencode.ai/install | bash -s -- --version $2"
      CURL_DIRS=("$HOME/.opencode/")
      ;;
    "Claude Code")
      BIN=claude
      INSTALL="curl -fsSL https://claude.ai/install.sh | bash -s $2"
      CURL_DIRS=("$HOME/.local/bin/" "$HOME/.local/share/claude/")
      ;;
    *) return 1 ;;
  esac
}

resolve() {  # <path>; follow symlinks (macOS has no readlink -f on older systems)
  python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

is_curl_install() {  # <bin path>
  local p d
  for p in "$1" "$(resolve "$1")"; do
    for d in "${CURL_DIRS[@]}"; do
      [[ "$p" == "$d"* ]] && return 0
    done
  done
  return 1
}

ask() {  # <question>; non-interactive counts as no
  local a
  [[ -t 0 ]] || return 1
  read -r -p "$1 [y/N] " a
  [[ "$a" == y || "$a" == Y ]]
}

run_install() {
  printf 'RUN      %s\n' "$INSTALL"
  bash -c "set -o pipefail; $INSTALL"
}

while IFS='|' read -r _ name _ ver _; do
  name="$(printf '%s' "$name" | sed 's/^ *//;s/ *$//')"
  pin="$(printf '%s' "$ver" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  [[ -n "$pin" ]] || { printf 'SKIP     %-12s no pinned version\n' "$name"; continue; }
  spec "$name" "$pin" || { printf 'SKIP     %-12s no installer known\n' "$name"; continue; }

  path="$(command -v "$BIN" || true)"
  if [[ -z "$path" ]]; then
    printf 'MISSING  %-12s installing %s\n' "$name" "$pin"
    run_install
    continue
  fi

  have="$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
  if [[ "$have" == "$pin" ]]; then
    printf 'OK       %-12s %s\n' "$name" "$pin"
  elif is_curl_install "$path"; then
    printf 'OUTDATED %-12s installed=%s pinned=%s\n' "$name" "${have:-?}" "$pin"
    if ask "Install $name $pin over $have?"; then run_install; fi
  else
    printf 'OUTDATED %-12s installed=%s pinned=%s at %s (not a curl install)\n' "$name" "${have:-?}" "$pin" "$path"
    printf '         update it with its own package manager, or remove it and rerun to use: %s\n' "$INSTALL"
  fi
done < <(grep '^|' "$HARNESSES" | grep -v '^| *[:-]*[ |-]*$' | sed '1d')
