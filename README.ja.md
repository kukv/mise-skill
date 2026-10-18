# mise-skill

[English](README.md)

GitHub リポジトリから [エージェントスキル](https://agentskills.io) を取得し、Claude Code と
Codex が読むディレクトリへリンクする [mise](https://mise.jdx.dev) の backend plugin。

```sh
mise plugins install skill https://github.com/kukv/mise-skill
```

```toml
# ~/.config/mise/config.toml
[env]
MISE_SKILL_AGENTS = "claude-code,codex"   # 既定: claude-code

[tools]
"skill:example/writing-guide" = "latest"
"skill:example/prose-lint" = { version = "latest", agents = ["claude-code"] }
"skill:example/code-search" = { version = "ref:main", skills = ["code-search", "code-search-outline"] }
"skill:foo/bar" = { version = "latest", dirs = ["~/somewhere/skills"] }
```

```sh
mise install
```

各スキルは mise の installs ディレクトリに展開され、`<dir>/<スキル名>` として symlink が
張られる。hook も追加のツールも要らない。

## 版

版はリポジトリのタグから先頭の `v` を除いたもの。タグのないリポジトリは ref で入れる:
`"ref:main"` または `"ref:<commit>"`。

## オプション

| オプション | 既定 | 意味 |
|---|---|---|
| `skills` | 見つかったすべてのスキル | リンクするスキル名（`SKILL.md` の `name:`） |
| `agents` | `MISE_SKILL_AGENTS`、なければ `claude-code` | リンク先にするエージェント |
| `dirs` | なし | 追加でリンクするディレクトリ（絶対パスか `~/...`） |
| `root` | `~` | エージェントのディレクトリの基準（絶対パスか `~/...`）。例: `"{{config_root}}"` |

| エージェント | ディレクトリ |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

## プロジェクト単位

プロジェクトの `mise.toml` で `root = "{{config_root}}"` と書くと、そのプロジェクトの
`.claude/skills` / `.agents/skills` にリンクする。`{{config_root}}` は mise がプロジェクトの
ディレクトリに展開するので、このファイルはコミットして共有できる。

```toml
# <project>/mise.toml
[tools]
"skill:example/writing-guide" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
```

版は mise の installs ディレクトリで共有し、ほかのプロジェクトで入れた版を使うときもリンクは
張られる（`mise install` 時か、activate したシェルでプロジェクトに入ったとき）。

- リンクはこのマシンの installs ディレクトリを指す。`.claude/skills/<スキル名>` と
  `.agents/skills/<スキル名>` は gitignore に入れる。
- プロジェクトの `mise.toml` からツールを消しても、リンクはその版を prune するまで残る。
- 手で消したリンクは `mise cache clear` のあとに張り直される。
- 1 つのプロジェクトで `mise install -f` すると、ほかのプロジェクトのリンクも外れ、それぞれで
  次に mise が動いたときに張り直される。

## リンクを最新に保つ

リンクは版のインストール時に張られ、アンインストール時に外れる。

| やりたいこと | 実行するもの |
|---|---|
| スキルを足す、新しい版に上げる | `mise install` / `mise upgrade` |
| `skills` / `agents` / `dirs` の変更を反映する | `mise install -f skill:owner/repo` |
| `ref:` で入れたもの（例: `ref:main`）をブランチの最新コミットに上げる | `mise install -f skill:owner/repo@ref:main` |
| スキルのリンクを外す | `[tools]` から消して `mise prune` |

mise-skill が作っていない既存のディレクトリや、生きているリンクには触れない。インストールは
警告を出してそれを飛ばす。別の `skill:` ツールが張ったリンクも同じで、2 つのツールが同じ名前の
スキルを持つときは先に入れた方が残る（`skills` で選ぶ）。同じ名前の切れたリンクは張り替える。

## 開発

```sh
mise install   # mise.toml で固定した開発ツール
mise run ci    # lint + test
```

`mise run lint` は [hk](https://hk.jdx.dev) で Lua（lua-language-server、stylua）、シェルのテスト
（shellcheck）、ワークフロー（actionlint）を検査する。`mise run lint-fix` は直せるものを直す。
`mise run test` は `tests/*.test.sh` をすべて実行し、最初の失敗で止まる。

テストは fixture リポジトリ bright-room-sandbox/mise-skill-fixtures の架空のスキルを install する。API のレート制限を避けるため、gh CLI のログイン
（または GITHUB_TOKEN）で認証する。

mise 2026.10.10 の Linux と macOS で動作を確認している。
