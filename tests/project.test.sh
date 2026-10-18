#!/bin/sh
# Project scope: root = "{{config_root}}" links into the agents' directories of each project that
# uses the tool.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
fx=skill:bright-room-sandbox/mise-skill-fixtures

# Lua's os.tmpname creates /tmp/lua_XXXXXX whatever TMPDIR says
luatmp() { find /tmp/ -maxdepth 1 -name 'lua_*' -user "$(id -u)" 2>/dev/null | sort; }
luatmp_before="$(luatmp)"

new_home project
echo '[tools]' | config
for p in a b c; do
  mkdir -p "$h/work/$p/sub"
  printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}", agents = ["claude-code", "codex"] }\n' \
    "$fx" > "$h/work/$p/mise.toml"
done

# the first project installs the version and is linked for both agents
(wd="$h/work/a" m install) >/dev/null 2>&1 || fail "a: install"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "a: claude-code link"
[ -f "$h/work/a/.agents/skills/alpha/SKILL.md" ] || fail "a: codex link"
[ -e "$h/.claude/skills/alpha" ] && fail "a: root should replace ~ for the agents"

# the second project reuses the installed version and is linked too, from a subdirectory
(wd="$h/work/b/sub" m install) >/dev/null 2>&1 || fail "b: install"
[ -f "$h/work/b/.claude/skills/alpha/SKILL.md" ] || fail "b: claude-code link"
[ -f "$h/work/b/.agents/skills/alpha/SKILL.md" ] || fail "b: codex link"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "b: a should stay linked"

# entering a project (shell activation) is enough
(wd="$h/work/c" m trust) >/dev/null 2>&1 || fail "c: trust"
(wd="$h/work/c" m hook-env -s zsh) >/dev/null 2>&1 || fail "c: hook-env"
[ -f "$h/work/c/.claude/skills/alpha/SKILL.md" ] || fail "c: alpha should be linked"

# a bad root for an installed version is a plain warning, not an error with a stack trace
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" > "$h/work/c/mise.toml"
out="$(wd="$h/work/c" m env 2>&1)" || fail "bad: mise env should still work"
echo "$out" | grep -q 'mise-skill: could not link' || fail "bad: should warn, got: $out"
echo "$out" | grep -q 'stack traceback' && fail "bad: should not raise, got: $out"

# install -f in one project unlinks the others until they run mise again
(wd="$h/work/b" m install -f "$fx@0.1.0") >/dev/null 2>&1 || fail "reinstall: install -f in b"
[ -f "$h/work/b/.claude/skills/alpha/SKILL.md" ] || fail "reinstall: b should be linked"
(wd="$h/work/a" m env) >/dev/null 2>&1 || fail "reinstall: env in a"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "reinstall: a should be linked again"

# removing the tool from every project and pruning removes the links of every project
for p in a b c; do echo '[tools]' > "$h/work/$p/mise.toml"; done
m prune >/dev/null 2>&1 || fail "prune"
for p in a b c; do
  [ -e "$h/work/$p/.claude/skills/alpha" ] && fail "prune: $p claude-code link should be gone"
  [ -e "$h/work/$p/.agents/skills/alpha" ] && fail "prune: $p codex link should be gone"
done

[ "$(luatmp)" = "$luatmp_before" ] || fail "tmp: os.tmpname files were left in /tmp"

# a relative root fails a fresh install
new_home bad-root
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad-root: install should fail"; fi
echo "$err" | grep -q 'root must be absolute or start with ~/: relative' ||
  fail "bad-root: error should name root, got: $err"

# without root, entering a project that pins an older installed version leaves the global link alone
new_home no-root
mkdir -p "$h/work/d"
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" > "$h/work/d/mise.toml"
(wd="$h/work/d" m install) >/dev/null 2>&1 || fail "no-root: install 0.1.0 in d"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "no-root: install 0.2.0"
m cache clear >/dev/null 2>&1 || fail "no-root: cache clear"
(wd="$h/work/d" m env) >/dev/null 2>&1 || fail "no-root: env in d"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$h/.local/share/mise/installs/skill-bright-room-sandbox-mise-skill-fixtures/0.2.0" ] ||
  fail "no-root: the global link should stay on 0.2.0"

echo "ok project"
