#!/usr/bin/env bash
# check-deps.sh — iterate the DEPENDENCIES.md table. Each Local version cell
# declares its own release source: "x.y.z (github owner/repo)" or
# "x.y.z (pypi package)". Cells without that form are skipped.
# Outdated rows are reported; edit the table manually.
#
# With --issues, sync one GitHub issue per outdated dependency: create when
# missing, comment + refresh the body only when the latest version changes,
# close when the dependency is current again. Needs gh plus GH_TOKEN (or a
# gh login) and GH_REPO (or an origin remote on github.com).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/DEPENDENCIES.md"

status=0
CREATE_ISSUES=0
for arg in "$@"; do
  case "$arg" in
    --issues) CREATE_ISSUES=1 ;;
    *) printf 'usage: %s [--issues]\n' "$0" >&2; exit 2 ;;
  esac
done

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

# --- issue sync (only used with --issues) ------------------------------------

build_issue_body() {  # <name> <docs> <latest> <source>
  cat <<EOF
$1 is out of date.

- docs version: $2
- latest: $3
- source: $4

Update the row in DEPENDENCIES.md, then close this issue. If it is closed while still outdated, the daily check opens a new one. This issue updates only when the latest version changes.

Checked on $(date -u +%Y-%m-%d).

<!-- checked-latest: $3 -->
EOF
}

open_issue_number() {  # <name>; first open "deps: <name> outdated" issue number, else empty
  gh issue list --repo "$GH_REPO" --label dependencies --state open --limit 200 \
    --json number,title --jq '.[] | select(.title == "deps: '"$1"' outdated") | .number' \
    2>/dev/null | head -1 || true
}

current_marker() {  # <body>; the checked-latest marker value, if present
  printf '%s' "$1" | sed -n 's/.*checked-latest: \([^ ]*\).*/\1/p'
}

if [[ "$CREATE_ISSUES" == 1 ]]; then
  command -v gh >/dev/null || { printf -- '--issues: gh CLI not found in PATH\n' >&2; exit 2; }
  GH_TOKEN="${GH_TOKEN:-$(gh auth token 2>/dev/null || true)}"
  [[ -n "$GH_TOKEN" ]] || { printf -- '--issues: no GH_TOKEN and no gh login\n' >&2; exit 2; }
  GH_REPO="${GH_REPO:-$(git -C "$ROOT" remote get-url origin 2>/dev/null | sed -E 's#.*github\.com[:/]##; s#\.git$##')}"
  [[ -n "$GH_REPO" ]] || { printf -- '--issues: no GH_REPO and no origin remote\n' >&2; exit 2; }
  gh label create dependencies --description "Outdated dependency tracking" --color BFD4F2 --repo "$GH_REPO" >/dev/null 2>&1 || true
fi

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
    if [[ "$CREATE_ISSUES" == 1 ]]; then
      n="$(open_issue_number "$name")"
      if [[ -n "$n" ]]; then
        gh issue close "$n" --repo "$GH_REPO" --comment "Up to date at $localv, closing." >/dev/null
        printf 'CLOSED   %-16s issue #%s\n' "$name" "$n"
      fi
    fi
  else
    stale "$name" "$localv" "$latest ($src)"
    if [[ "$CREATE_ISSUES" == 1 ]]; then
      n="$(open_issue_number "$name")"
      if [[ -z "$n" ]]; then
        gh issue create --repo "$GH_REPO" --title "deps: $name outdated" \
          --body "$(build_issue_body "$name" "$localv" "$latest" "$src")" \
          --label dependencies >/dev/null
        printf 'CREATED  %-16s issue for latest=%s\n' "$name" "$latest"
      else
        body="$(gh issue view "$n" --repo "$GH_REPO" --json body --jq .body 2>/dev/null || true)"
        old="$(current_marker "$body")"
        if [[ "$old" != "$latest" ]]; then
          if [[ -n "$old" ]]; then
            comment="Latest is now $latest (was $old). Docs still at $localv."
          else
            comment="Latest is now $latest. Docs still at $localv."
          fi
          gh issue comment "$n" --repo "$GH_REPO" --body "$comment" >/dev/null
          gh issue edit "$n" --repo "$GH_REPO" \
            --body "$(build_issue_body "$name" "$localv" "$latest" "$src")" >/dev/null
          printf 'UPDATED  %-16s issue #%s latest=%s\n' "$name" "$n" "$latest"
        fi
      fi
    fi
  fi
done < <(grep '^|' "$DEPS" | grep -v '^| *[:-]*[ |-]*$' | sed '1d')

exit "$status"
