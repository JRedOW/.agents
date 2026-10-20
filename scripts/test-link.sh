#!/bin/bash
# test-link.sh — integration tests for scripts/link.sh .ignore support.
#
# link.sh derives its hub from its own location, so the script is copied
# into a sandbox hub and run there with --linkup, which never touches $HOME.
# Usage: scripts/test-link.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "PASS    $1"; }
die()  { echo "FAIL    $1" >&2; fail=1; }

# assert_link <case> <hub> <harness> <type> <name> <linked|absent>
assert_link() {
  local p="$2/harnesses/$3/$4/$5"
  if [ "$6" = linked ]; then
    if [ -L "$p" ] && [ -e "$p" ]; then
      pass "$1"
    else
      die "$1 ($p missing or broken)"
    fi
  else
    if [ ! -L "$p" ] && [ ! -e "$p" ]; then
      pass "$1"
    else
      die "$1 ($p exists)"
    fi
  fi
}

make_skill() { mkdir -p "$1" && printf 'x\n' > "$1/SKILL.md"; }

# run <hub> <harness> [stderr-file]
run() {
  (cd "$1" && /bin/bash scripts/link.sh --linkup --harness "$2") \
    2>"${3:-/dev/null}" >/dev/null
}

# --- hub 1: rule matching ------------------------------------------------------

H1="$TMP/hub1"
mkdir -p "$H1/scripts" "$H1/harnesses/claude" "$H1/harnesses/opencode"
cp "$ROOT/scripts/link.sh" "$H1/scripts/link.sh"
make_skill "$H1/skills/plain"
make_skill "$H1/skills/scratch"
make_skill "$H1/skills/caveman/ultracave"
make_skill "$H1/skills/caveman/cavecrew"
mkdir -p "$H1/agents/keep" "$H1/agents/.hidden"
for f in draft.md notes.md claudeonly.md ghost.md; do
  printf 'x\n' > "$H1/agents/$f"
done
printf 'x\n' > "$H1/agents/keep/inside.md"
printf 'x\n' > "$H1/agents/.hidden/dotted.md"
printf 'ultracave\n' > "$H1/skills/caveman/.ignore"

cat > "$H1/.ignore" <<'EOF'
# comments and blanks are skipped

scratch/
draft*
notes.md
!notes.md
keep/
!keep/
[claude] claudeonly.md
[cladude] ghost
EOF

run "$H1" claude "$TMP/claude.err"
run "$H1" opencode

assert_link "plain skill links (claude)"       "$H1" claude   skills plain            linked
assert_link "plain skill links (opencode)"     "$H1" opencode skills plain            linked
assert_link "root dir rule prunes skill"       "$H1" claude   skills scratch           absent
assert_link "nested .ignore excludes skill"    "$H1" claude   skills ultracave         absent
assert_link "unlisted grouped skill links"     "$H1" opencode skills cavecrew          linked
assert_link "glob rule drops agent"            "$H1" claude   agents draft.md          absent
assert_link "negation re-includes file"        "$H1" claude   agents notes.md          linked
assert_link "dir rule + negation re-includes"  "$H1" claude   agents inside.md         linked
assert_link "tag-scoped rule (claude)"         "$H1" claude   agents claudeonly.md     absent
assert_link "tag-scoped rule (opencode)"       "$H1" opencode agents claudeonly.md     linked
assert_link "dot dirs are no longer special"   "$H1" claude   agents dotted.md         linked
assert_link "unknown tag rule is inert"        "$H1" claude   agents ghost.md          linked
if grep -q "unknown harness 'cladude'" "$TMP/claude.err"; then
  pass "unknown tag warns with file and line"
else
  die "unknown tag warns with file and line"
fi

# --- hub 2: pruning an existing link when .ignore appears ----------------------

H2="$TMP/hub2"
mkdir -p "$H2/scripts" "$H2/harnesses/claude" "$H2/harnesses/opencode"
cp "$ROOT/scripts/link.sh" "$H2/scripts/link.sh"
make_skill "$H2/skills/scratch"

run "$H2" claude
assert_link "link exists before .ignore"       "$H2" claude   skills scratch           linked
printf 'scratch/\n' > "$H2/.ignore"
run "$H2" claude
assert_link "new .ignore prunes existing link" "$H2" claude   skills scratch           absent

if [ "$fail" -eq 0 ]; then
  echo "all tests passed"
fi
exit "$fail"
