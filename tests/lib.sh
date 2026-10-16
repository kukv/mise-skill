# Shared helpers for the tests. Source it: . "$(dirname "$0")/lib.sh"
# Each test runs mise in a throwaway HOME with this checkout linked as the "skill" plugin.
# GITHUB_TOKEN / MISE_GITHUB_TOKEN are passed through so GitHub API calls are authenticated.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
h=""

fail() { echo "FAIL: $*" >&2; exit 1; }

# m <args...>: run mise inside $h with no XDG / MISE_* overrides leaking in from the caller.
m() {
  (cd "$h/work" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    -u MISE_DATA_DIR -u MISE_CONFIG_DIR -u MISE_CACHE_DIR -u MISE_STATE_DIR -u MISE_ENV \
    -u MISE_SKILL_AGENTS MISE_CEILING_PATHS="$h" HOME="$h" MISE_YES=1 mise "$@")
}

# new_home <name>: make a fresh HOME under $tmp, make it current, link the plugin.
new_home() {
  h="$tmp/$1"
  mkdir -p "$h/.config/mise" "$h/work"
  m plugins link skill "$repo" >/dev/null
}

# config: write stdin as the global mise config of the current HOME.
config() { cat > "$h/.config/mise/config.toml"; }
