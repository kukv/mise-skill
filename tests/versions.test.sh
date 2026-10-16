#!/bin/sh
# BackendListVersions: tags become versions without the leading "v"; a repo without tags errors.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

new_home versions
out="$(m ls-remote skill:kukv/mise-skill-fixtures)"
[ "$out" = "$(printf '0.1.0\n0.2.0')" ] || fail "ls-remote should list exactly 0.1.0 then 0.2.0 (no v, no draft-v9), got: $out"
latest="$(m latest skill:kukv/mise-skill-fixtures)"
[ "$latest" = "0.2.0" ] || fail "latest should be 0.2.0, got: $latest"

if err="$(m ls-remote skill:kukv/structure 2>&1)"; then
  fail "ls-remote on a repo without tags should fail"
fi
echo "$err" | grep -q 'ref:main' || fail "error should suggest ref:main, got: $err"

echo "ok versions"
