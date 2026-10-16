#!/bin/sh
# BackendListVersions: tags become versions without the leading "v"; a repo without tags errors.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

new_home versions
out="$(m ls-remote skill:coji/natural-japanese)"
echo "$out" | grep -qx '1.5.2' || fail "ls-remote should list 1.5.2, got: $out"
echo "$out" | grep -q '^v' && fail "versions must not start with v: $out"
[ "$(echo "$out" | head -n1)" = "0.1.0" ] || fail "versions must be oldest first, got: $out"
echo "$out" | grep -q 'skill-v2-draft' && fail "non-version tags must be dropped: $out"
latest="$(m latest skill:coji/natural-japanese)"
echo "$latest" | grep -q '^[0-9]' || fail "latest should be a version, got: $latest"

if err="$(m ls-remote skill:ast-grep/agent-skill 2>&1)"; then
  fail "ls-remote on a repo without tags should fail"
fi
echo "$err" | grep -q 'ref:main' || fail "error should suggest ref:main, got: $err"

echo "ok versions"
