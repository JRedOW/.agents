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

# --- hub 3: leaves at any nesting depth ----------------------------------------

H3="$TMP/hub3"
mkdir -p "$H3/scripts" "$H3/harnesses/claude" "$H3/harnesses/opencode" "$H3/agents/group/one"
cp "$ROOT/scripts/link.sh" "$H3/scripts/link.sh"
make_skill "$H3/skills/suite/eng/tdd"
make_skill "$H3/skills/suite/plat/grill"
printf 'x\n' > "$H3/agents/group/one/nested.md"
printf 'x\n' > "$H3/agents/group/two.md"
printf 'scratch/\n' > "$H3/.ignore"
make_skill "$H3/skills/suite/eng/scratch"

run "$H3" claude
assert_link "deep-nested skill links"          "$H3" claude   skills tdd             linked
assert_link "second deep-nested skill links"   "$H3" claude   skills grill           linked
assert_link "deep-nested agent file links"     "$H3" claude   agents nested.md       linked
assert_link "shallow agent file links"         "$H3" claude   agents two.md          linked
assert_link "deep .ignore rule prunes skill"   "$H3" claude   skills scratch         absent

# --- hub 4: profile dirs -------------------------------------------------------

H4="$TMP/hub4"
mkdir -p "$H4/scripts" "$H4/harnesses/claude" "$H4/harnesses/opencode"
cp "$ROOT/scripts/link.sh" "$H4/scripts/link.sh"
make_skill "$H4/skills/skillA"
make_skill "$H4/skills/skillB"
make_skill "$H4/skills/ghost2"
make_skill "$H4/skills/baseonly"
mkdir -p "$H4/agents/blender"
printf 'x\n' > "$H4/agents/blender/bl.md"
printf '*\n<blender> !*\n' > "$H4/agents/blender/.ignore"
printf 'x\n' > "$H4/harnesses/claude/CLAUDE.md"
printf '{"base":true,"gone":1,"o":{"keep":1,"x":1},"a":[1,2]}\n' > "$H4/harnesses/claude/settings.template.json"
printf '{"base":true}\n' > "$H4/harnesses/opencode/opencode.json"
mkdir -p "$H4/harnesses/opencode/plugins/caveman" "$H4/harnesses/opencode/profiles/blender"
printf '{"profile":true}\n' > "$H4/harnesses/opencode/profiles/blender/opencode.template.json"
mkdir -p "$H4/harnesses/claude/profiles/blender"
printf '{"profile":true,"gone":null,"o":{"x":2,"new":{"y":null}},"a":[2,3]}\n' \
  > "$H4/harnesses/claude/profiles/blender/settings.template.json"

cat > "$H4/.ignore" <<'EOF'
<blender> skillA/
[claude] <blender> skillB/
<codign> ghost2/
<default> baseonly/
EOF

cat > "$H4/PROFILES.md" <<'EOF'
# Profiles

| Profile | Harnesses | Description |
|---|---|---|
| blender | claude, opencode | test |
| solo | claude | claude only |
EOF

CB="claude/profiles/blender"
OB="opencode/profiles/blender"
run "$H4" claude "$TMP/profile.err"
run "$H4" opencode
assert_link "base never fires profile rules"         "$H4" claude   skills skillA       linked
assert_link "base excludes profile-only agent"       "$H4" claude   agents bl.md        absent
assert_link "profile rule fires in profile dir"      "$H4" "$CB"    skills skillA       absent
assert_link "harness+profile AND fires (claude)"     "$H4" "$CB"    skills skillB       absent
assert_link "profile re-includes agent"              "$H4" "$CB"    agents bl.md        linked
assert_link "profile rule fires (opencode)"          "$H4" "$OB"    skills skillA       absent
assert_link "harness+profile AND holds (opencode)"   "$H4" "$OB"    skills skillB       linked
assert_link "claude profile links CLAUDE.md"         "$H4" "$CB"    .       CLAUDE.md   linked
assert_link "opencode profile links plugin dir"      "$H4" "$OB"    plugins caveman     linked
assert_link "missing base AGENTS.md not linked"      "$H4" "$OB"    .       AGENTS.md   absent
assert_link "harness list limits profile dirs"       "$H4" opencode profiles solo       absent
assert_link "claude-only profile built"              "$H4" claude/profiles/solo skills skillA linked
# expect_json <case> <file> <jq-filter>: filter must print true for the file
expect_json() {
  if [ -f "$2" ] && [ ! -L "$2" ] && [ "$(jq -c "$3" "$2")" = true ]; then
    pass "$1"
  else
    die "$1 ($2)"
  fi
}
expect_json "opencode.json merged from base + template" "$H4/harnesses/$OB/opencode.json" \
  '. == {"base":true,"profile":true}'
expect_json "settings deep-merged onto base template" "$H4/harnesses/$CB/settings.json" \
  '. == {"base":true,"o":{"keep":1,"x":2,"new":{}},"a":[1,2,3],"profile":true}'
expect_json "settings without template copy base" "$H4/harnesses/claude/profiles/solo/settings.json" \
  '.base == true and .gone == 1'
printf '{"edited":true}\n' > "$H4/harnesses/$OB/opencode.json"
run "$H4" opencode
expect_json "seeded opencode.json never overwritten" "$H4/harnesses/$OB/opencode.json" \
  '. == {"edited":true}'
if grep -q "unknown profile 'codign'" "$TMP/profile.err"; then
  pass "unknown profile warns with name"
else
  die "unknown profile warns with name"
fi
assert_link "unknown profile rule is inert"          "$H4" "$CB"    skills ghost2       linked
assert_link "default rule fires in base"             "$H4" claude   skills baseonly     absent
assert_link "default rule inert in profile"          "$H4" "$CB"    skills baseonly     linked
if grep -q "unknown profile 'default'" "$TMP/profile.err"; then
  die "default tag is a known profile"
else
  pass "default tag is a known profile"
fi

# removing a profile prunes hub links but keeps the dir and its state
sed -i.bak '/^| solo/d' "$H4/PROFILES.md"
run "$H4" claude "$TMP/removed.err"
assert_link "removed profile links pruned"           "$H4" claude/profiles/solo skills skillA absent
if [ -f "$H4/harnesses/claude/profiles/solo/settings.json" ] \
  && grep -q "no longer a claude profile" "$TMP/removed.err"; then
  pass "removed profile keeps state and warns"
else
  die "removed profile keeps state and warns"
fi

# a bad PROFILES.md row aborts before anything is touched
H5="$TMP/hub5"
mkdir -p "$H5/scripts" "$H5/harnesses/claude"
cp "$ROOT/scripts/link.sh" "$H5/scripts/link.sh"
make_skill "$H5/skills/plain"
printf '| Profile | Harnesses |\n|---|---|\n| bad | cladude |\n' > "$H5/PROFILES.md"
if run "$H5" claude "$TMP/bad.err"; then
  die "unknown harness in PROFILES.md errors"
elif grep -q "unknown harness 'cladude'" "$TMP/bad.err"; then
  pass "unknown harness in PROFILES.md errors"
else
  die "unknown harness in PROFILES.md errors"
fi
assert_link "bad PROFILES.md touches nothing"        "$H5" claude   skills plain        absent
printf '| Profile | Harnesses |\n|---|---|\n| default | claude |\n' > "$H5/PROFILES.md"
if ! run "$H5" claude "$TMP/reserved.err" && grep -q "'default' is reserved" "$TMP/reserved.err"; then
  pass "default profile name is reserved"
else
  die "default profile name is reserved"
fi

# --- merge oracle --------------------------------------------------------------
# Independent of link.sh's merge_json: compare leaf sets. A leaf is
# [path without array indices, value, inside-array] for each non-null scalar.
# The output must hold every template leaf, every base leaf not overridden or
# deleted by the template, and nothing else.
cat > "$TMP/oracle.jq" <<'EOF'
def leaves: [paths(scalars) as $p | getpath($p) as $v | select($v != null)
  | [($p | map(select(type == "string"))), $v, ($p | any(type == "number"))]] | unique;
($b[0] | leaves) as $bl | ($p[0] | leaves) as $pl | ($o[0] | leaves) as $ol
| ([$pl[] | select(.[2] | not) | .[0]]
   + [$p[0] | paths(. == null) | map(select(type == "string"))]) as $over
| [$bl[] | select(.[0] as $k | $over | all(. as $d | $k[:($d | length)] != $d))] as $kept
| ($pl - $ol) == [] and ($kept - $ol) == [] and ($ol - $pl - $kept) == []
EOF

# check_merge <case> <base> <patch> <out> [expect-fail]
check_merge() {
  local ok=0
  if jq -n --slurpfile b "$2" --slurpfile p "$3" --slurpfile o "$4" -f "$TMP/oracle.jq" \
    | grep -qx true; then
    ok=1
  fi
  if { [ "$ok" -eq 1 ] && [ -z "${5-}" ]; } || { [ "$ok" -eq 0 ] && [ -n "${5-}" ]; }; then
    pass "$1"
  else
    die "$1 ($4)"
  fi
}

check_merge "oracle agrees with synthetic merge" "$H4/harnesses/claude/settings.template.json" \
  "$H4/harnesses/$CB/settings.template.json" "$H4/harnesses/$CB/settings.json"
printf '{"base":true,"o":{"x":2,"new":{}},"a":[1,2,3],"profile":true}\n' > "$TMP/missing.json"
check_merge "oracle catches a dropped base key" "$H4/harnesses/claude/settings.template.json" \
  "$H4/harnesses/$CB/settings.template.json" "$TMP/missing.json" fail
printf '{"base":true,"o":{"keep":1,"x":2,"new":{}},"a":[1,2,3],"profile":true,"z":0}\n' > "$TMP/extra.json"
check_merge "oracle catches an invented key" "$H4/harnesses/claude/settings.template.json" \
  "$H4/harnesses/$CB/settings.template.json" "$TMP/extra.json" fail
printf '{"base":true,"gone":1,"o":{"keep":1,"x":2,"new":{}},"a":[1,2,3],"profile":true}\n' > "$TMP/undeleted.json"
check_merge "oracle catches a null that did not delete" "$H4/harnesses/claude/settings.template.json" \
  "$H4/harnesses/$CB/settings.template.json" "$TMP/undeleted.json" fail
printf '{"base":true,"o":{"keep":1,"x":2,"new":{}},"a":[2,3],"profile":true}\n' > "$TMP/replaced.json"
check_merge "oracle catches a replaced array" "$H4/harnesses/claude/settings.template.json" \
  "$H4/harnesses/$CB/settings.template.json" "$TMP/replaced.json" fail
printf '{"base":true,"o":{"keep":1,"x":1,"new":{}},"a":[1,2,3],"profile":true}\n' > "$TMP/unpatched.json"
check_merge "oracle catches an ignored override" "$H4/harnesses/claude/settings.template.json" \
  "$H4/harnesses/$CB/settings.template.json" "$TMP/unpatched.json" fail

# --- hub 6: this repo's real configs -------------------------------------------

H6="$TMP/hub6"
mkdir -p "$H6/scripts"
cp "$ROOT/scripts/link.sh" "$H6/scripts/link.sh"
cp "$ROOT/PROFILES.md" "$H6/PROFILES.md"
for f in "$ROOT"/harnesses/claude/settings.template.json "$ROOT"/harnesses/opencode/opencode.json \
  "$ROOT"/harnesses/*/profiles/*/*.template.json; do
  [ -f "$f" ] || continue
  mkdir -p "$H6/$(dirname "${f#"$ROOT"/}")"
  cp "$f" "$H6/${f#"$ROOT"/}"
done
run "$H6" all

if cmp -s "$H6/harnesses/claude/settings.template.json" "$H6/harnesses/claude/settings.json"; then
  pass "real base settings.json is the template byte for byte"
else
  die "real base settings.json is the template byte for byte"
fi
for tpl in "$H6"/harnesses/*/profiles/*/*.template.json; do
  [ -f "$tpl" ] || continue
  case "$tpl" in
    */settings.template.json)
      base="$H6/harnesses/claude/settings.template.json"
      out="${tpl%/*}/settings.json" ;;
    */opencode.template.json)
      base="$H6/harnesses/opencode/opencode.json"
      out="${tpl%/*}/opencode.json" ;;
    *) continue ;;
  esac
  rel="${out#"$H6"/}"
  check_merge "real $rel holds base + template, nothing else" "$base" "$tpl" "$out"
  cp "$out" "$TMP/first.json"
  rm "$out"
  run "$H6" all
  if cmp -s "$TMP/first.json" "$out"; then
    pass "real $rel regenerates byte for byte"
  else
    die "real $rel regenerates byte for byte"
  fi
  # live copies are seed-once and may hold hand edits, so drift only warns
  if [ -f "$ROOT/$rel" ] && ! cmp -s <(jq -S . "$ROOT/$rel") <(jq -S . "$out"); then
    echo "WARN    $ROOT/$rel differs from a fresh merge; delete it and rerun link.sh if unedited" >&2
  fi
done

# profiles.sh defines one alias per listed harness
aliases="$(AGENTS_HUB="$H4" bash -c 'shopt -s expand_aliases; source "$1"; alias' _ "$ROOT/scripts/profiles.sh")"
if printf '%s\n' "$aliases" | grep -q "claude-blender=.*CLAUDE_CONFIG_DIR=.*/harnesses/claude/profiles/blender" \
  && printf '%s\n' "$aliases" | grep -q "opencode-blender=.*OPENCODE_CONFIG_DIR=" \
  && ! printf '%s\n' "$aliases" | grep -q "solo"; then
  pass "profiles.sh defines launchers"
else
  die "profiles.sh defines launchers"
fi

if [ "$fail" -eq 0 ]; then
    echo "all tests passed"
fi
exit "$fail"
