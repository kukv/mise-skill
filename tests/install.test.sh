#!/bin/sh
# BackendInstall: fetch a tag or ref into install_path and select skills.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }

new_home install
echo '[tools]' | config

# a tagged version, with or without the "v" in the tag
m install skill:kukv/mise-skill-fixtures@0.1.0 >/dev/null 2>&1 || fail "install fixtures@0.1.0"
[ -f "$(installs)/skill-kukv-mise-skill-fixtures/0.1.0/skills/alpha/SKILL.md" ] ||
  fail "alpha SKILL.md should be extracted"
[ -f "$(installs)/skill-kukv-mise-skill-fixtures/0.1.0/nested/deep/gamma/SKILL.md" ] ||
  fail "gamma SKILL.md should be extracted"

# a ref (a branch here)
m install skill:kukv/mise-skill-fixtures@ref:invalid-name >/dev/null 2>&1 || fail "install fixtures@ref:invalid-name"
[ -f "$(installs)/skill-kukv-mise-skill-fixtures/ref-invalid-name/skills/alpha/SKILL.md" ] ||
  fail "the ref install should be extracted"

# no SKILL.md at all
if err="$(m install skill:kukv/mise-skill-fixtures@ref:no-skills 2>&1)"; then
  fail "a repository without SKILL.md should fail"
fi
echo "$err" | grep -q 'no SKILL.md' || fail "error should say no SKILL.md, got: $err"

# skills option names a skill that does not exist (fresh home: "latest" would match an installed version)
new_home unknown-skill
printf '[tools]\n"skill:kukv/mise-skill-fixtures" = { version = "latest", skills = ["nope"] }\n' | config
if err="$(m install 2>&1)"; then
  fail "an unknown name in skills should fail"
fi
echo "$err" | grep -q 'nope' || fail "error should name the unknown skill, got: $err"

# an unknown version
if m install skill:kukv/mise-skill-fixtures@0.0.0-nope >/dev/null 2>&1; then
  fail "an unknown version should fail"
fi

echo "ok install"
