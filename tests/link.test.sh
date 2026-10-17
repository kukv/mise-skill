#!/bin/sh
# Linking: where links go, what they point at, and what is left alone.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }
fx=skill:bright-room-sandbox/mise-skill-fixtures
dir=skill-bright-room-sandbox-mise-skill-fixtures

# default agent: claude-code only
new_home default
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "default: install"
for s in alpha beta gamma; do
  [ -L "$h/.claude/skills/$s" ] || fail "default: $s link in ~/.claude/skills"
done
[ -f "$h/.claude/skills/alpha/SKILL.md" ] || fail "default: link should reach SKILL.md"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.1.0" ] ||
  fail "default: marker should hold install_path"
[ -e "$h/.agents/skills/alpha" ] && fail "default: codex is not a default agent"

# MISE_SKILL_AGENTS from [env], creating ~/.agents/skills that does not exist yet
new_home env
printf '[env]\nMISE_SKILL_AGENTS = "claude-code,codex"\n[tools]\n"%s" = "0.1.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "env: install"
[ -L "$h/.claude/skills/alpha" ] || fail "env: claude-code link"
[ -L "$h/.agents/skills/alpha" ] || fail "env: codex link"

# agents option overrides MISE_SKILL_AGENTS; dirs adds a path; skills selects
new_home options
cat <<'EOT' | config
[env]
MISE_SKILL_AGENTS = "claude-code,codex"
[tools]
"skill:bright-room-sandbox/mise-skill-fixtures" = { version = "0.1.0", skills = ["gamma"], agents = ["codex"], dirs = ["~/extra/skills"] }
EOT
m install >/dev/null 2>&1 || fail "options: install"
[ -L "$h/.agents/skills/gamma" ] || fail "options: codex link"
[ -L "$h/extra/skills/gamma" ] || fail "options: dirs link"
[ -e "$h/.claude/skills/gamma" ] && fail "options: agents should replace the env default"
[ -e "$h/.agents/skills/alpha" ] && fail "options: skills should select only gamma"

# unknown agent and relative dirs fail the install
new_home bad
printf '[tools]\n"%s" = { version = "0.1.0", agents = ["nope"] }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad: unknown agent should fail"; fi
echo "$err" | grep -q 'unknown agent nope' || fail "bad: error should name the agent, got: $err"
printf '[tools]\n"%s" = { version = "0.1.0", dirs = ["relative/skills"] }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad: relative dirs should fail"; fi
echo "$err" | grep -q 'relative/skills' || fail "bad: error should name the dir, got: $err"

# a real directory with the same name is left alone
new_home conflict
mkdir -p "$h/.claude/skills/alpha"
echo mine > "$h/.claude/skills/alpha/SKILL.md"
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "conflict: install should still succeed"
[ -L "$h/.claude/skills/alpha" ] && fail "conflict: the real directory must not be replaced"
[ "$(cat "$h/.claude/skills/alpha/SKILL.md")" = mine ] || fail "conflict: contents changed"

# a dangling link with the same name is replaced
new_home dangling
mkdir -p "$h/.claude/skills"
ln -s "$h/gone" "$h/.claude/skills/alpha"
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "dangling: install"
[ -f "$h/.claude/skills/alpha/SKILL.md" ] || fail "dangling: link should be replaced"

# a link that another tool placed is left alone, and the other skills are still linked
new_home other-tool
other="$(installs)/skill-someone-else/1.0.0"
mkdir -p "$other/alpha" "$h/.claude/skills"
printf '%s' "$other" > "$other/alpha/.mise-skill"
ln -s "$other/alpha" "$h/.claude/skills/alpha"
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" | config
out="$(m install 2>&1)" || fail "other-tool: install should succeed, got: $out"
echo "$out" | grep -q 'another tool links it' || fail "other-tool: should warn, got: $out"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$other" ] ||
  fail "other-tool: alpha must still point at the other tool"
[ -L "$h/.claude/skills/beta" ] || fail "other-tool: beta should be linked"
m uninstall "$fx@0.1.0" >/dev/null 2>&1 || fail "other-tool: uninstall"
[ -L "$h/.claude/skills/alpha" ] || fail "other-tool: uninstall must keep the other tool's link"

# dirs on another filesystem: links are made and replaced there, with no temporary link left
fs_of() { df -P "$1" | awk 'NR == 2 { print $1 }'; }
if [ -d /dev/shm ] && [ -w /dev/shm ] && [ "$(fs_of /dev/shm)" != "$(fs_of "$tmp")" ]; then
  xdev="$(mktemp -d /dev/shm/mise-skill-test.XXXXXX)"
  trap 'rm -rf "$tmp" "$xdev"' EXIT
  new_home xdev
  mkdir "$xdev/existing"
  printf '[tools]\n"%s" = { version = "0.1.0", dirs = ["%s/existing", "%s/new/skills"] }\n' "$fx" "$xdev" "$xdev" | config
  m install >/dev/null 2>&1 || fail "xdev: install"
  for d in "$xdev/existing" "$xdev/new/skills"; do
    [ -f "$d/alpha/SKILL.md" ] || fail "xdev: $d/alpha should be linked"
  done
  printf '[tools]\n"%s" = { version = "0.2.0", dirs = ["%s/existing"] }\n' "$fx" "$xdev" | config
  m install >/dev/null 2>&1 || fail "xdev: install 0.2.0"
  [ "$(cat "$xdev/existing/alpha/.mise-skill")" = "$(installs)/$dir/0.2.0" ] ||
    fail "xdev: link should be replaced with 0.2.0"
  [ "$(ls "$xdev/existing")" = "$(printf 'alpha\nbeta\ngamma')" ] ||
    fail "xdev: only the skills should be left, got: $(ls "$xdev/existing")"
else
  echo "skip xdev: /dev/shm is not a separate filesystem"
fi

# a failed install (typo in skills) does not leave a version that plain `mise install` skips
new_home typo
printf '[tools]\n"%s" = { version = "0.1.0", skills = ["gamm"] }\n' "$fx" | config
m install >/dev/null 2>&1 && fail "typo: install should fail"
printf '[tools]\n"%s" = { version = "0.1.0", skills = ["gamma"] }\n' "$fx" | config
m install >/dev/null 2>&1 || fail "typo: install after the fix"
[ -L "$h/.claude/skills/gamma" ] || fail "typo: plain mise install after the fix should link"

# upgrading relinks to the new version; removing the old version keeps the new link
new_home upgrade
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "upgrade: install 0.1.0"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "upgrade: install 0.2.0"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.2.0" ] ||
  fail "upgrade: link should point at 0.2.0"
m uninstall "$fx@0.1.0" >/dev/null 2>&1 || fail "upgrade: uninstall 0.1.0"
[ -L "$h/.claude/skills/alpha" ] || fail "upgrade: removing 0.1.0 must keep the 0.2.0 link"

# install -f applies changed options and drops links that are no longer wanted
cat <<'EOT' | config
[tools]
"skill:bright-room-sandbox/mise-skill-fixtures" = { version = "0.2.0", agents = ["claude-code", "codex"] }
EOT
m install -f "$fx@0.2.0" >/dev/null 2>&1 || fail "reinstall: add codex"
[ -L "$h/.agents/skills/alpha" ] || fail "reinstall: codex link should appear"
cat <<'EOT' | config
[tools]
"skill:bright-room-sandbox/mise-skill-fixtures" = { version = "0.2.0", agents = ["codex"] }
EOT
m install -f "$fx@0.2.0" >/dev/null 2>&1 || fail "reinstall: drop claude-code"
[ -e "$h/.claude/skills/alpha" ] && fail "reinstall: claude-code link should be gone"
[ -L "$h/.agents/skills/alpha" ] || fail "reinstall: codex link should stay"

# removing the tool from the config and pruning removes its links, and only its links
mkdir -p "$h/.agents/skills/handmade"
echo '[tools]' | config
m prune >/dev/null 2>&1 || fail "prune"
[ -e "$h/.agents/skills/alpha" ] && fail "prune: link should be gone"
[ -d "$h/.agents/skills/handmade" ] || fail "prune: other entries must stay"

# a skill whose name would escape the skills directory is skipped; the others are linked
new_home name
printf '[tools]\n"%s" = "ref:invalid-name"\n' "$fx" | config
out="$(m install 2>&1)" || fail "name: install should succeed, got: $out"
echo "$out" | grep -q 'invalid skill name' || fail "name: should warn about the invalid name, got: $out"
for s in alpha beta gamma; do
  [ -L "$h/.claude/skills/$s" ] || fail "name: $s should be linked"
done
for p in "$h/.claude/escape" "$h/escape" "$h/.claude/skills/escape"; do
  [ -e "$p" ] && fail "name: $p must not exist"
done
stray="$(find "$h" -name escape -not -path '*/installs/*' -not -path '*/downloads/*')"
[ -z "$stray" ] || fail "name: nothing named escape may exist outside installs, got: $stray"

echo "ok link"
