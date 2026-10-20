#!/bin/bash
# test-sync.sh — integration tests for scripts/sync-upstream.sh.
#
# Like test-link.sh, the script under test is copied into a sandbox hub (it
# derives its hub from its own location). Upstream fixtures are local git
# repos fetched via file:// URLs, so tests are offline. The --via skills test
# uses `npx skills` against a local fixture dir and is skipped when Node
# < 22.20 or npx is missing. link.sh invocations are redirected at a sandbox
# $HOME so the real home is never touched.
# Usage: scripts/test-sync.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail=0
pass() { echo "PASS    $1"; }
skip() { echo "SKIP    $1"; }
die()  { echo "FAIL    $1" >&2; fail=1; }

assert_dir() {
  if [ -d "$2" ]; then pass "$1"; else die "$1 ($2 missing)"; fi
}
assert_gone() {
  if [ ! -e "$2" ] && [ ! -L "$2" ]; then pass "$1"; else die "$1 ($2 still present)"; fi
}
assert_symlink_to() {
  if [ -L "$2" ] && [ "$(readlink "$2")" = "$3" ]; then
    pass "$1"
  else
    die "$1 ($2 is not a symlink to $3)"
  fi
}

make_skill() {
  mkdir -p "$1"
  printf -- '---\nname: %s\ndescription: test\n---\n\nbody\n' "$(basename "$1")" >"$1/SKILL.md"
}

# new_hub <path>: fresh sandbox hub with the scripts under test copied inside.
new_hub() {
  local hub="$1"
  mkdir -p \
    "$hub/scripts" \
    "$hub/harnesses/claude/agents" "$hub/harnesses/claude/commands" "$hub/harnesses/claude/skills" \
    "$hub/harnesses/opencode/agents" "$hub/harnesses/opencode/commands" "$hub/harnesses/opencode/skills"
  cp "$ROOT/scripts/sync-upstream.sh" "$hub/scripts/"
  cp "$ROOT/scripts/link.sh" "$hub/scripts/"
}

# new_upstream <path>: git repo with skills/{a,b}, agents, commands, extra plugin.
new_upstream() {
  local up="$1"
  make_skill "$up/skills/a"
  make_skill "$up/skills/b"
  mkdir -p "$up/agents" "$up/commands"
  printf 'agent\n' >"$up/agents/x.md"
  printf 'agent2\n' >"$up/agents/y.md"
  printf 'command\n' >"$up/commands/x.md"
  mkdir -p "$up/extra/plugin"
  printf 'entry\n' >"$up/extra/plugin/index.js"
  printf 'note\n' >"$up/extra/notes.md"
  git init -q -b main "$up"
  git -C "$up" add -A
  git -C "$up" -c user.email=t@localhost -c user.name=test commit -qm init
}

# sync <hub> <args...>: run sync-upstream.sh inside a sandbox hub with a
# sandbox $HOME so link.sh harness-level links never reach the real home.
# Callers direct stdout/stderr as needed.
sync() {
  local hub="$1"
  shift
  (cd "$hub" && HOME="$TMP/home" bash scripts/sync-upstream.sh "$@")
}

mkdir -p "$TMP/home"
UP="$TMP/up"
new_upstream "$UP"
UP_URL="file://$UP"

# 1. git fetch mode: skills/agents/commands all sync, upstream extras ignored,
#    and --no-link keeps link.sh (and the sandbox home) untouched.
H1="$TMP/hub-no-link"
new_hub "$H1"
OUT=$(sync "$H1" testdep "$UP_URL" --no-link)
assert_dir "git fetch syncs skills" "$H1/skills/testdep/a"
assert_dir "git fetch syncs second skill" "$H1/skills/testdep/b"
assert_dir "git fetch syncs agents" "$H1/agents/testdep"
[ -f "$H1/agents/testdep/x.md" ] && pass "git fetch syncs agent file" || die "agent file missing"
assert_gone "upstream extra/ dir not vendored without --raw" "$H1/extra"
assert_gone "--no-link leaves home untouched" "$TMP/home/.claude"
echo "$OUT" | grep -q "synced skills/testdep/" && pass "--no-link summary printed" || die "summary missing: $OUT"

# 2. rsync --delete prunes stale vendored items on update.
mkdir -p "$H1/skills/testdep/stale" && printf 'x\n' >"$H1/skills/testdep/stale/SKILL.md"
sync "$H1" testdep "$UP_URL" --no-link skills >/dev/null
assert_gone "--delete removes upstream-deleted skill" "$H1/skills/testdep/stale"
assert_dir "--delete keeps upstream-present skill" "$H1/skills/testdep/a"

# 3. probe NAME validation before touching anything.
if sync "$H1" "bad/name" "$UP_URL" --no-link >/dev/null 2>&1; then
  die "NAME with slash rejected"
else
  pass "NAME with slash rejected"
fi

# 4. --raw mapping syncs nonstandard paths with --delete semantics.
H2="$TMP/hub-raw"
new_hub "$H2"
mkdir -p "$H2/harnesses/opencode/plugins/testplug"
printf 'old\n' >"$H2/harnesses/opencode/plugins/testplug/old.js"
sync "$H2" testdep "$UP_URL" --raw extra/plugin:harnesses/opencode/plugins/testplug \
  --raw extra/notes.md:harnesses/opencode/plugins/testplug --no-link skills >/dev/null
assert_dir "--raw syncs upstream dir" "$H2/harnesses/opencode/plugins/testplug"
[ -f "$H2/harnesses/opencode/plugins/testplug/index.js" ] && pass "--raw syncs plugin file" || die "plugin file missing"
[ -f "$H2/harnesses/opencode/plugins/testplug/notes.md" ] && pass "--raw copies upstream file" || die "notes file missing"
assert_gone "--raw --delete prunes destination-only file" "$H2/harnesses/opencode/plugins/testplug/old.js"

# 5. full run without --no-link: link.sh refreshes sandbox-home harness links.
H3="$TMP/hub-link"
new_hub "$H3"
sync "$H3" testdep "$UP_URL" skills agents commands >/dev/null
assert_symlink_to "link.sh harness link created" "$TMP/home/.claude" "$H3/harnesses/claude"
assert_symlink_to "link.sh skill item link created" "$H3/harnesses/claude/skills/a" "../../../skills/testdep/a"
assert_symlink_to "link.sh agent item link created" "$H3/harnesses/claude/agents/x.md" "../../../agents/testdep/x.md"

# 6. duplicate skill names across hub source groups warn.
H4="$TMP/hub-dup"
new_hub "$H4"
make_skill "$H4/skills/other/a"
sync "$H4" testdep "$UP_URL" --no-link skills >/dev/null 2>"$TMP/dup.err" || true
grep -q "duplicate skill name 'a'" "$TMP/dup.err" \
  && pass "collision warning emitted" || die "no collision warning: $(cat "$TMP/dup.err")"

# 7. --via skills against a local pack fixture; requires Node >= 22.20.
NODE_OK=false
if command -v npx >/dev/null 2>&1; then
  NODE_OK=$(node -p '
    const a = process.versions.node.split(".").map(Number);
    const b = [22, 20, 0];
    a[0] > b[0] || (a[0] === b[0] && (a[1] > b[1] || (a[1] === b[1] && a[2] >= b[2])))
  ' 2>/dev/null || echo false)
fi
  UP2="$TMP/up-pack"
  mkdir -p "$UP2/engineering/alpha" "$UP2/productivity/beta"
  make_skill "$UP2/engineering/alpha"
  make_skill "$UP2/productivity/beta"
  git init -q -b main "$UP2"
  git -C "$UP2" add -A
  git -C "$UP2" -c user.email=t@localhost -c user.name=test commit -qm init
  git -C "$UP2" -c user.email=t@localhost -c user.name=test tag v1.0.0
  make_skill "$UP2/engineering/gamma"
  git -C "$UP2" add -A
  git -C "$UP2" -c user.email=t@localhost -c user.name=test commit -qm gamma

  if [ "$NODE_OK" != "true" ]; then
    skip "--via skills fetch (Node >= 22.20 unavailable)"
  else
    H5="$TMP/hub-via"
    new_hub "$H5"
    if OUT=$(sync "$H5" viadep "$UP2" --via skills --no-link skills); then
      assert_dir "via skills fetch syncs grouped skill 1" "$H5/skills/viadep/alpha"
      assert_dir "via skills fetch syncs grouped skill 2" "$H5/skills/viadep/beta"
      grep -q "name: alpha" "$H5/skills/viadep/alpha/SKILL.md" \
        && pass "via skills fetch keeps frontmatter" || die "frontmatter mangled"
    else
      die "--via skills fetch failed: $OUT"
    fi

    # 8. --via skills with #REF pins content to the tagged commit.
    H5b="$TMP/hub-via-ref"
    new_hub "$H5b"
    if OUT=$(sync "$H5b" viref "$UP2#v1.0.0" --via skills --no-link skills); then
      assert_dir "via ref syncs tagged skill" "$H5b/skills/viref/alpha"
      assert_gone "via ref excludes post-tag skill" "$H5b/skills/viref/gamma"
    else
      die "--via skills with ref failed: $OUT"
    fi
  fi

  # 9. type=item lists vendor only the listed items; .ignore survives.
  H6="$TMP/hub-filter"
  new_hub "$H6"
  mkdir -p "$H6/skills/testdep"
  printf '# local rules\n' >"$H6/skills/testdep/.ignore"
  sync "$H6" testdep "$UP_URL" --no-link skills=a agents=x >/dev/null
  assert_dir "filter syncs listed skill" "$H6/skills/testdep/a"
  assert_gone "filter prunes unlisted skill" "$H6/skills/testdep/b"
  assert_gone "filter prunes unlisted agent file" "$H6/agents/testdep/y.md"
  [ -f "$H6/agents/testdep/x.md" ] && pass "filter keeps listed agent (name without .md)" \
    || die "agent name-without-.md filter match failed"
  [ -f "$H6/skills/testdep/.ignore" ] && pass "filter keeps .ignore" || die ".ignore destroyed"

  # 10. --raw file src to a dst that is not a directory renames the file.
  H7="$TMP/hub-rename"
  new_hub "$H7"
  sync "$H7" testdep "$UP_URL" --no-link \
    --raw extra/notes.md:harnesses/opencode/plugins/renamed/renamed.cjs >/dev/null
  [ -f "$H7/harnesses/opencode/plugins/renamed/renamed.cjs" ] \
    && pass "--raw renames file to exact dst path" || die "--raw rename failed"
  grep -q 'note' "$H7/harnesses/opencode/plugins/renamed/renamed.cjs" \
    && pass "--raw renamed file has upstream content" || die "renamed file content wrong"

  # 11. #REF pins git-mode syncs to a tag; unknown refs fail loudly.
  git -C "$UP" -c user.email=t@localhost -c user.name=test tag v1.2.3
  printf 'changed\n' >>"$UP/skills/a/SKILL.md"
  git -C "$UP" add -A
  git -C "$UP" -c user.email=t@localhost -c user.name=test commit -qm post-tag
  H8="$TMP/hub-refs"
  new_hub "$H8"
  sync "$H8" testdep "$UP_URL#v1.2.3" --no-link skills >/dev/null
  if grep -q 'changed' "$H8/skills/testdep/a/SKILL.md"; then
    die "pinned sync picked up post-tag content"
  else
    pass "pinned sync uses tagged content"
  fi
  sync "$H8" testdep "$UP_URL" --no-link skills >/dev/null
  grep -q 'changed' "$H8/skills/testdep/a/SKILL.md" \
    && pass "unpinned sync tracks main" || die "main sync missing post-tag content"
  if sync "$H8" testdep "$UP_URL#v9.9.9" --no-link skills >/dev/null 2>&1; then
    die "unknown ref accepted"
  else
    pass "unknown ref rejected"
  fi

if [ "$fail" -eq 0 ]; then
  echo "all tests passed"
else
  echo "$fail test(s) failed" >&2
  exit 1
fi
