# mise-skill

[日本語](README.ja.md)

A [mise](https://mise.jdx.dev) backend plugin that installs [agent skills](https://agentskills.io)
from GitHub repositories and links them where Claude Code and Codex look for them.

```sh
mise plugins install skill https://github.com/kukv/mise-skill
```

```toml
# ~/.config/mise/config.toml
[env]
MISE_SKILL_AGENTS = "claude-code,codex"   # default: claude-code

[tools]
"skill:example/writing-guide" = "latest"
"skill:example/prose-lint" = { version = "latest", agents = ["claude-code"] }
"skill:example/code-search" = { version = "ref:main", skills = ["code-search", "code-search-outline"] }
"skill:foo/bar" = { version = "latest", dirs = ["~/somewhere/skills"] }
```

```sh
mise install
```

Each skill is extracted under mise's installs directory and symlinked as
`<dir>/<skill name>`. Nothing else is needed: no hooks, no extra tools.

## Versions

Versions are the repository's tags without a leading `v`. A repository without tags is
installed by ref: `"ref:main"` or `"ref:<commit>"`.

## Options

| Option | Default | Meaning |
|---|---|---|
| `skills` | every skill found | Skill names (the `name:` in `SKILL.md`) to link |
| `agents` | `MISE_SKILL_AGENTS`, else `claude-code` | Agents to link for |
| `dirs` | none | Extra directories (absolute or `~/...`) to link into |

| Agent | Directory |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

## Keeping links in sync

Links are made when a version is installed and removed when it is uninstalled.

| To | Run |
|---|---|
| add a skill or move to a new version | `mise install` / `mise upgrade` |
| apply changed `skills` / `agents` / `dirs` | `mise install -f skill:owner/repo` |
| move a `ref:` install (e.g. `ref:main`) to the branch's latest commit | `mise install -f skill:owner/repo@ref:main` |
| remove a skill's links | delete it from `[tools]`, then `mise prune` |

An existing directory or a working link that mise-skill did not create is never touched; the
install warns and skips it. A dangling link with the same name is replaced.

## Development

```sh
mise install   # dev tools pinned in mise.toml
mise run ci    # lint + test
```

`mise run lint` checks Lua (lua-language-server, stylua), the shell tests (shellcheck) and the
workflows (actionlint) with [hk](https://hk.jdx.dev); `mise run lint-fix` fixes what it can.
`mise run test` runs every `tests/*.test.sh` and stops at the first failure.

The tests install fictional skills from the fixture repository kukv/mise-skill-fixtures. They authenticate with the gh CLI's login (or GITHUB_TOKEN) to avoid API rate limits.

Tested with mise 2026.10.10 on Linux and macOS.
