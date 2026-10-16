# Contributing

Thanks for taking the time to improve mise-skill.

## Getting started

mise-skill is a [mise](https://mise.jdx.dev) backend plugin: Lua 5.1 hooks (`metadata.lua`,
`hooks/`, `lib/`) that mise runs, and black-box tests written in POSIX sh (`tests/`). You
need mise; it installs everything else pinned in `mise.toml` (hk, pkl, stylua,
lua-language-server, actionlint, shellcheck).

```bash
mise install          # the dev tools pinned in mise.toml
mise run ci           # everything CI checks: lint + test
mise run lint         # hk: lua-language-server, stylua, shellcheck, actionlint
mise run lint-fix     # let hk fix what it can (stylua formatting)
mise run test         # every tests/*.test.sh, stopping at the first failure
```

The tests run mise in a throwaway `HOME` with this checkout linked as the `skill` plugin, and
install real GitHub repositories. They authenticate with the gh CLI's login (or
`GITHUB_TOKEN`) to avoid API rate limits.

To try a change by hand, link the checkout as the plugin:

```bash
mise plugins link --force skill .
```

Do not commit while `mise run ci` fails.

## Before you change code

The design lives in
[docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md](docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md):
what is in and out of scope, the options, and the rules for which links mise-skill may
create, replace or remove. Read it first. A change that goes beyond it — a new option, a
new agent, a different linking rule — needs an issue to agree on the design before code.

- Designs: `docs/superpowers/specs/`
- Plans: `docs/superpowers/plans/`

Both are written with the [superpowers](https://github.com/obra/superpowers) plugin for
Claude Code: its `brainstorming` skill produces the design and its `writing-plans` skill
the plan. You do not need the plugin to contribute — the documents are plain Markdown —
but new ones should follow the same format and locations.

## Checking an install or link change

Passing tests are not enough for a change to what ends up on disk. Run it and look:

- `mise install` with the `[tools]` entry you changed, then `ls -l ~/.claude/skills`
  (and `~/.agents/skills` for codex, and any `dirs`);
- `mise install -f skill:owner/repo` after changing `skills` / `agents` / `dirs`;
- removing the entry and running `mise prune` — only the links mise-skill made go away;
- on macOS as well as Linux if you can. CI runs the tests on both.

## Pull requests

- CI runs on every pull request: `ci.yaml` (lint, and the tests on Linux and macOS) and
  `security.yml` (hidden-content scan, gitleaks, dependency scanning, zizmor, actionlint).
  All of them must pass.
- Pin any GitHub Action you add to a full commit SHA with a `# vX.Y.Z` comment. Renovate
  follows them, and the tools in `mise.toml`.
- Commit messages use a `feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `build:` /
  `ci:` / `chore:` prefix.
- Link the issue the pull request resolves (`Closes #123`).
- Label the pull request so it lands in the right section of the release notes — see
  [Releases](#releases).
- Review by the maintainer (`.github/CODEOWNERS`) is required before merge.

## Releases

mise installs the plugin from this repository's git history, so every merge to `main`
reaches users on their next `mise plugins update`. Releases are cut by the maintainer
from GitHub; their notes are generated from the labels on the merged pull requests,
following `.github/release.yaml`:

| Label                | Release notes section |
| -------------------- | --------------------- |
| `Impact: Breaking`   | Breaking Changes      |
| `Kind: Feature`      | New Features          |
| `Kind: Enhancement`  | Enhancement Updates   |
| `Kind: Bug Fix`      | Bug Fix               |
| `Kind: Dependencies` | dependency updates    |
| anything else        | Other Changes         |

`Meta: Release note ignored` keeps a pull request out of the notes. Tags are never moved
or reused once pushed.

## Use of AI

AI assistance is fine. Submitting what an AI produced without understanding it is not.

Generating a submission takes seconds; verifying one takes a person's time. Sending
unverified output moves that cost onto the maintainer and takes time away from the review
this project actually needs.

Before you open an issue or a pull request, you are expected to have read the output,
verified it against this repository, and be able to explain and defend it. You are the
author of what you submit, whatever tool helped you write it.

Issues and pull requests that appear to be unreviewed AI output — invented options,
files or APIs that do not exist, a diff that does not follow from the description,
boilerplate that does not engage with this project — are **closed without notice and
without individual explanation**. That judgment is the maintainer's, and there is no
appeal process; you are welcome to open a new issue or pull request that shows your own
reasoning.

Closing one does not mean the underlying point was worthless. If a closed issue or pull
request contains something useful, the maintainer may take it up — as an issue raised by
the maintainer, or by merging or rewriting the change — without notice and without credit
to the original submitter. Anything you submit is licensed under the
[MIT License](LICENSE), and opening an issue or pull request here means you accept this
handling.

## Reporting problems

- A security issue: see [SECURITY.md](SECURITY.md).
- A bug or a feature request: open an issue from the templates.

By contributing you agree that your contributions are licensed under the
[MIT License](LICENSE). Everyone taking part is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
