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

A project can have its own skills: put them in the project's `mise.toml` with
`root = "{{config_root}}"`, and they are linked into the project's `.claude/skills` /
`.agents/skills` instead of your home.

```toml
# <project>/mise.toml
[tools]
"skill:example/prose-lint" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
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
| `root` | none | Base of the agents' directories (absolute or `~/...`); `{{config_root}}` in a project |

The directories are under your home, or under `root` when it is set.

| Agent | Directory |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

## Keeping links in sync

Links are made when a version is installed and on each mise run, and removed when it is uninstalled.

| To | Run |
|---|---|
| add a skill or move to a new version | `mise install` / `mise upgrade` |
| apply changed `skills` / `agents` / `dirs` / `root` | nothing: the next mise run applies them |
| switch to a version that is already installed | `mise cache clear` |
| move a `ref:` install (e.g. `ref:main`) to the branch's latest commit | `mise install -f skill:owner/repo@ref:main` |
| remove a skill's links | delete it from `[tools]`, then `mise prune` |

An existing directory or a working link that mise-skill did not create is never touched; the
install warns and skips it. The same goes for a link that another `skill:` tool placed: when two
tools provide a skill with the same name, the one installed first keeps it (use `skills` to choose).
A dangling link with the same name is replaced.

## Scopes

Each config links its own skills: the global config (`~/.config/mise/config.toml`) into your home,
a project's `mise.toml` with `root = "{{config_root}}"` into the project. mise does not tell a
plugin which config a tool comes from, and caches the plugin's result per set of options, so a
project needs `root`: a project config without it is an error.

- Links point into this machine's mise installs directory, so gitignore `.claude/skills/<name>` and
  `.agents/skills/<name>` in the repository.
- In a shell with `mise activate`, entering a project is enough to link its skills.
- A tool removed from a config keeps its links until that version is pruned.
- A link deleted by hand is not made again until `mise cache clear`.
- `mise install -f` in one project unlinks the version in the other projects until mise runs there.
- Two configs that point different versions of a tool at the same `dirs` entry swap the links on
  each run.

## Development

```sh
mise install   # dev tools pinned in mise.toml
mise run ci    # lint + test
```

`mise run lint` checks Lua (lua-language-server, stylua), the shell tests (shellcheck) and the
workflows (actionlint) with [hk](https://hk.jdx.dev); `mise run lint-fix` fixes what it can.
`mise run test` runs every `tests/*.test.sh` and stops at the first failure.

The tests install fictional skills from the fixture repository bright-room-sandbox/mise-skill-fixtures. They authenticate with the gh CLI's login (or GITHUB_TOKEN) to avoid API rate limits.

Tested with mise 2026.10.10 on Linux and macOS.
