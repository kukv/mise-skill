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

# changing skills in one project changes only that project's links
printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}", agents = ["claude-code", "codex"], skills = ["alpha"] }\n' \
  "$fx" > "$h/work/a/mise.toml"
(wd="$h/work/a" m env) >/dev/null 2>&1 || fail "skills: env in a"
[ -e "$h/work/a/.claude/skills/beta" ] && fail "skills: beta should be gone from a"
[ -L "$h/work/a/.claude/skills/alpha" ] || fail "skills: alpha should stay in a"
[ -L "$h/work/b/.claude/skills/beta" ] || fail "skills: b should keep beta"

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

# a relative root fails a fresh install
new_home bad-root
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad-root: install should fail"; fi
echo "$err" | grep -q 'root must be absolute or start with ~/: relative' ||
  fail "bad-root: error should name root, got: $err"

# a project on an older version than the global config: each keeps its own version, although
# installing in the project makes mise call ExecEnv for both versions with the project's options
new_home pinned
mkdir -p "$h/work/p"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "pinned: global install"
printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}" }\n' "$fx" > "$h/work/p/mise.toml"
(wd="$h/work/p" m install) >/dev/null 2>&1 || fail "pinned: install in p"
[ "$(cat "$h/work/p/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.1.0" ] ||
  fail "pinned: p should link 0.1.0"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.2.0" ] ||
  fail "pinned: ~ should stay on 0.2.0"

echo "ok project"
