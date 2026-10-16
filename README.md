# mise-skill

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
"skill:coji/natural-japanese" = "latest"
"skill:nanaism/yomiyasu" = { version = "latest", agents = ["claude-code"] }
"skill:ast-grep/agent-skill" = { version = "ref:main", skills = ["ast-grep", "ast-grep-outline"] }
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
for t in tests/*.test.sh; do sh "$t" || exit 1; done
```

The tests use real GitHub repositories. They authenticate with the gh CLI's login (or GITHUB_TOKEN) to avoid API rate limits.

Tested with mise 2026.10.10 on Linux and macOS.
