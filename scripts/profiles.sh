# Launchers for the profiles in PROFILES.md. Source from .zshrc or .bashrc:
#
#   source ~/.agents/scripts/profiles.sh
#
# Defines <harness>-<profile> aliases (claude-blender, opencode-blender) that
# point the harness at harnesses/<harness>/profiles/<profile>/. Set
# AGENTS_HUB first if the hub is not at ~/.agents. link.sh validates
# PROFILES.md; this only reads it.

_agents_hub="${AGENTS_HUB:-$HOME/.agents}"
if [ -f "$_agents_hub/PROFILES.md" ]; then
  while read -r _agents_h _agents_p; do
    case "$_agents_h" in
      claude) _agents_var=CLAUDE_CONFIG_DIR ;;
      opencode) _agents_var=OPENCODE_CONFIG_DIR ;;
      *) continue ;;
    esac
    alias "$_agents_h-$_agents_p=$_agents_var='$_agents_hub/harnesses/$_agents_h/profiles/$_agents_p' $_agents_h"
  done < <(awk -F'|' '/^\|/ {
    p = $2; h = $3
    gsub(/[[:space:]]/, "", p); gsub(/[[:space:]]/, "", h)
    if (p == "" || p == "Profile" || p ~ /^:?-+:?$/) next
    n = split(h, hs, ",")
    for (i = 1; i <= n; i++) print hs[i], p
  }' "$_agents_hub/PROFILES.md")
fi
unset _agents_hub _agents_h _agents_p _agents_var
