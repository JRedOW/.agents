#!/usr/bin/env bash
# check-deps.sh — iterate the DEPENDENCIES.md table. Each Local version cell
# declares its own release source: "x.y.z (github owner/repo)" or
# "x.y.z (pypi package)". Cells without that form are skipped.
# Outdated rows are reported; edit the table manually.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/DEPENDENCIES.md"

status=0

found()  { printf 'OK       %-16s docs=%s latest=%s\n' "$1" "$2" "$3"; }
stale()  { printf 'OUTDATED %-16s docs=%s latest=%s\n' "$1" "$2" "$3"; status=1; }
unknown(){ printf 'UNKNOWN  %-16s %s\n' "$1" "$2"; }
skip()   { printf 'SKIP     %-16s %s\n' "$1" "$2"; }

gh_latest() {  # <owner/repo>; empty when the repo has no releases
  curl -fsSL "https://api.github.com/repos/$1/releases/latest" 2>/dev/null |
    python3 -c 'import json,sys
d = json.load(sys.stdin)
print("" if "tag_name" not in d else d["tag_name"])' 2>/dev/null || true
}
pypi_latest() {  # <package>
  curl -fsSL "https://pypi.org/pypi/$1/json" 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["info"]["version"])' 2>/dev/null || true
}

# iterate data rows of the table (skip header + separator); process
# substitution keeps `status` exported from the loop subshell
while IFS='|' read -r _ dep repo ver _; do
  localv="" src="" kind="" target="" latest=""  # reset per row (set -u)
  name="$(printf '%s' "$dep" | sed 's/^ *//;s/ *$//')"
  name="${name%% (*}"
  name="${name//\`/}"  # strip backticks from `pkg` style names

  # expected cell form: "x.y.z (github owner/repo)" or "x.y.z (pypi package)"
  src="$(printf '%s' "$ver" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+ \((github|pypi) [^)]+\)' | head -1 || true)"
  if [[ -n "$src" ]]; then
    localv="$(printf '%s' "$ver" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
    src="${src#*(}"
    src="${src%)}"
    kind="${src%% *}"
    target="${src#* }"
  else
    skip "$name" "no checkable \"version (source target)\" cell"
    continue
  fi

  case "$kind" in
    github) latest="$(gh_latest "$target")" ;;
    pypi)   latest="$(pypi_latest "$target")" ;;
  esac
  latest="${latest#v}"

  if [[ -z "$latest" ]]; then
    unknown "$name" "no releases found for $target"
  elif [[ "$localv" == "$latest" ]]; then
    found "$name" "$localv" "$latest ($src)"
  else
    stale "$name" "$localv" "$latest ($src)"
  fi
done < <(grep '^|' "$DEPS" | grep -v '^| *[:-]*[ |-]*$' | sed '1d')

exit "$status"
