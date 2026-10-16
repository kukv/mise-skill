#!/bin/sh
# BackendInstall: fetch a tag or ref into install_path and select skills.
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }

new_home install
echo '[tools]' | config

# a tagged version, with or without the "v" in the tag
m install skill:coji/natural-japanese@1.5.2 >/dev/null 2>&1 || fail "install natural-japanese@1.5.2"
[ -f "$(installs)/skill-coji-natural-japanese/1.5.2/skills/natural-japanese/SKILL.md" ] ||
  fail "natural-japanese SKILL.md should be extracted"

# a ref on a repository without tags
m install skill:ast-grep/agent-skill@ref:main >/dev/null 2>&1 || fail "install agent-skill@ref:main"
[ -f "$(installs)/skill-ast-grep-agent-skill/ref-main/ast-grep/skills/outline/SKILL.md" ] ||
  fail "agent-skill should be extracted"

# no SKILL.md at all
if err="$(m install skill:jdx/mise-backend-plugin-template@ref:main 2>&1)"; then
  fail "a repository without SKILL.md should fail"
fi
echo "$err" | grep -q 'no SKILL.md' || fail "error should say no SKILL.md, got: $err"

# skills option names a skill that does not exist
printf '[tools]\n"skill:nanaism/yomiyasu" = { version = "latest", skills = ["nope"] }\n' | config
if err="$(m install 2>&1)"; then
  fail "an unknown name in skills should fail"
fi
echo "$err" | grep -q 'nope' || fail "error should name the unknown skill, got: $err"

# an unknown version
if m install skill:coji/natural-japanese@0.0.0-nope >/dev/null 2>&1; then
  fail "an unknown version should fail"
fi

echo "ok install"
