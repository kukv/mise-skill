#!/bin/sh
# Project scope: a project config links into the project with root = "{{config_root}}", and is an
# error without it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }
fx=skill:bright-room-sandbox/mise-skill-fixtures
dir=skill-bright-room-sandbox-mise-skill-fixtures

# a project config without root is an error, and does not keep the global config from linking
new_home no-root
echo '[tools]' | config
mkdir -p "$h/work/d"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" > "$h/work/d/mise.toml"
if err="$(wd="$h/work/d" m install 2>&1)"; then fail "no-root: install in d should fail"; fi
echo "$err" | grep -q 'without root; add root' || fail "no-root: install error should ask for root, got: $err"
m install "$fx@0.2.0" >/dev/null 2>&1 || fail "no-root: install by arguments"
m cache clear >/dev/null 2>&1 || fail "no-root: cache clear"
out="$(wd="$h/work/d" m env 2>&1)" || true
echo "$out" | grep -q 'without root; add root' || fail "no-root: mise env in d should ask for root, got: $out"
[ -e "$h/work/d/.claude/skills/alpha" ] && fail "no-root: d must not be linked"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" | config
m env >/dev/null 2>&1 || fail "no-root: global env"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.2.0" ] ||
  fail "no-root: the global config should still link 0.2.0"

echo "ok project"
