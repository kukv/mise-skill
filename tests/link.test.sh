#!/bin/sh
# Linking: where links go, what they point at, and what is left alone.
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }

# default agent: claude-code only
new_home default
printf '[tools]\n"skill:coji/natural-japanese" = "1.5.2"\n' | config
m install >/dev/null 2>&1 || fail "default: install"
[ -L "$h/.claude/skills/natural-japanese" ] || fail "default: link in ~/.claude/skills"
[ -f "$h/.claude/skills/natural-japanese/SKILL.md" ] || fail "default: link should reach SKILL.md"
[ "$(cat "$h/.claude/skills/natural-japanese/.mise-skill")" = "$(installs)/skill-coji-natural-japanese/1.5.2" ] ||
  fail "default: marker should hold install_path"
[ -e "$h/.agents/skills/natural-japanese" ] && fail "default: codex is not a default agent"

# MISE_SKILL_AGENTS from [env], creating ~/.agents/skills that does not exist yet
new_home env
printf '[env]\nMISE_SKILL_AGENTS = "claude-code,codex"\n[tools]\n"skill:coji/natural-japanese" = "1.5.2"\n' | config
m install >/dev/null 2>&1 || fail "env: install"
[ -L "$h/.claude/skills/natural-japanese" ] || fail "env: claude-code link"
[ -L "$h/.agents/skills/natural-japanese" ] || fail "env: codex link"

# agents option overrides MISE_SKILL_AGENTS; dirs adds a path; skills selects
new_home options
cat <<'EOT' | config
[env]
MISE_SKILL_AGENTS = "claude-code,codex"
[tools]
"skill:ast-grep/agent-skill" = { version = "ref:main", skills = ["ast-grep-outline"], agents = ["codex"], dirs = ["~/extra/skills"] }
EOT
m install >/dev/null 2>&1 || fail "options: install"
[ -L "$h/.agents/skills/ast-grep-outline" ] || fail "options: codex link"
[ -L "$h/extra/skills/ast-grep-outline" ] || fail "options: dirs link"
[ -e "$h/.claude/skills/ast-grep-outline" ] && fail "options: agents should replace the env default"
[ -e "$h/.agents/skills/ast-grep" ] && fail "options: skills should select only ast-grep-outline"

# unknown agent and relative dirs fail the install
new_home bad
printf '[tools]\n"skill:coji/natural-japanese" = { version = "1.5.2", agents = ["nope"] }\n' | config
if err="$(m install 2>&1)"; then fail "bad: unknown agent should fail"; fi
echo "$err" | grep -q 'unknown agent nope' || fail "bad: error should name the agent, got: $err"
printf '[tools]\n"skill:coji/natural-japanese" = { version = "1.5.2", dirs = ["relative/skills"] }\n' | config
if err="$(m install 2>&1)"; then fail "bad: relative dirs should fail"; fi
echo "$err" | grep -q 'relative/skills' || fail "bad: error should name the dir, got: $err"

# a real directory with the same name is left alone
new_home conflict
mkdir -p "$h/.claude/skills/natural-japanese"
echo mine > "$h/.claude/skills/natural-japanese/SKILL.md"
printf '[tools]\n"skill:coji/natural-japanese" = "1.5.2"\n' | config
m install >/dev/null 2>&1 || fail "conflict: install should still succeed"
[ -L "$h/.claude/skills/natural-japanese" ] && fail "conflict: the real directory must not be replaced"
[ "$(cat "$h/.claude/skills/natural-japanese/SKILL.md")" = mine ] || fail "conflict: contents changed"

# a dangling link with the same name is replaced
new_home dangling
mkdir -p "$h/.claude/skills"
ln -s "$h/gone" "$h/.claude/skills/natural-japanese"
printf '[tools]\n"skill:coji/natural-japanese" = "1.5.2"\n' | config
m install >/dev/null 2>&1 || fail "dangling: install"
[ -f "$h/.claude/skills/natural-japanese/SKILL.md" ] || fail "dangling: link should be replaced"

# a failed install (typo in skills) does not leave a version that plain `mise install` skips
new_home typo
printf '[tools]\n"skill:coji/natural-japanese" = { version = "1.5.2", skills = ["natural-japanes"] }\n' | config
m install >/dev/null 2>&1 && fail "typo: install should fail"
printf '[tools]\n"skill:coji/natural-japanese" = { version = "1.5.2", skills = ["natural-japanese"] }\n' | config
m install >/dev/null 2>&1 || fail "typo: install after the fix"
[ -L "$h/.claude/skills/natural-japanese" ] || fail "typo: plain mise install after the fix should link"

echo "ok link"
