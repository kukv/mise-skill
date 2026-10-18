#!/bin/sh
# Project scope: root = "{{config_root}}" links into the agents' directories of each project that
# uses the tool.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
fx=skill:bright-room-sandbox/mise-skill-fixtures

new_home project
echo '[tools]' | config
for p in a b c; do
  mkdir -p "$h/work/$p/sub"
  printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}", agents = ["claude-code", "codex"] }\n' \
    "$fx" > "$h/work/$p/mise.toml"
done

# the first project installs the version and is linked for both agents
wd="$h/work/a" m install >/dev/null 2>&1 || fail "a: install"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "a: claude-code link"
[ -f "$h/work/a/.agents/skills/alpha/SKILL.md" ] || fail "a: codex link"
[ -e "$h/.claude/skills/alpha" ] && fail "a: root should replace ~ for the agents"

# a relative root fails a fresh install
new_home bad-root
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad-root: install should fail"; fi
echo "$err" | grep -q 'root must be absolute or start with ~/: relative' ||
  fail "bad-root: error should name root, got: $err"

echo "ok project"
