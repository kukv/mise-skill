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

プロジェクトだけで使うスキルは、そのプロジェクトの `mise.toml` に `root = "{{config_root}}"` を
付けて書く。リンク先がホームではなく、プロジェクトの `.claude/skills` / `.agents/skills` になる。

```toml
# <project>/mise.toml
[tools]
"skill:example/prose-lint" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
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
| `root` | なし | エージェントのディレクトリの基準（絶対パスか `~/...`）。プロジェクトでは `{{config_root}}` |

| エージェント | ディレクトリ |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

ディレクトリはホームの下、`root` があれば `root` の下にある。

## リンクを最新に保つ

リンクは、版のインストール時と、mise がその版を新しいオプションの組み合わせ（別の設定や変更後のオプション）で初めて使うときに張られ、アンインストール時に外れる。

| やりたいこと | 実行するもの |
|---|---|
| スキルを足す、新しい版に上げる | `mise install` / `mise upgrade` |
| `skills` / `agents` / `dirs` / `root` の変更を反映する（新しいオプションの組み合わせになるとき） | 何もしない（次に mise が動いたときに反映される） |
| 入れ済みの版に切り替える、以前使ったオプションに戻す、`MISE_SKILL_AGENTS` を変える | `mise cache clear` |
| `ref:` で入れたもの（例: `ref:main`）をブランチの最新コミットに上げる | `mise install -f skill:owner/repo@ref:main` |
| スキルのリンクを外す | `[tools]` から消して `mise prune` |

mise-skill が作っていない既存のディレクトリや、生きているリンクには触れない。インストールは
警告を出してそれを飛ばす。別の `skill:` ツールが張ったリンクも同じで、2 つのツールが同じ名前の
スキルを持つときは先に入れた方が残る（`skills` で選ぶ）。同じ名前の切れたリンクは張り替える。

## スコープ

リンクは設定ごとに張られる。グローバル設定（`~/.config/mise/config.toml`）のスキルはホームに、
`root = "{{config_root}}"` を付けたプロジェクトの `mise.toml` のスキルはそのプロジェクトに張られる。
mise はツールがどの設定に書かれたかをプラグインに渡さず、プラグインの結果をオプションの値ごとに
キャッシュする。そのため、プロジェクトでは `root` が要る。`root` の無いプロジェクトの設定はエラーになる。

- リンクはこのマシンの mise の installs ディレクトリを指す。リポジトリでは `.claude/skills/<名前>` と
  `.agents/skills/<名前>` を gitignore する。
- `mise activate` したシェルでは、プロジェクトに入っただけでそのスキルがリンクされる。
- 設定から消したツールのリンクは、その版を prune するまで残る。
- 手で消したリンクは、`mise cache clear` するまで張り直されない。
- 1 つのプロジェクトで `mise install -f` すると、ほかのプロジェクトのその版のリンクは、そこで mise が
  動くまで外れる。
- 2 つの設定が、同じツールの違う版を同じ `dirs` に向けると、mise が動くたびにリンクが張り替わる。

0.1 からの更新: プラグインを更新したら、`mise cache clear` を 1 度実行する。古いキャッシュが残ると、
mise が新しいプラグインを呼ばない。`root` の無いプロジェクトの `mise.toml` に書いた `skill:` ツールは、
以前は `~` にリンクされたが、今はエラーになる。`root = "{{config_root}}"` を足すか、ツールを
グローバル設定に移す。0.1 が張ったリンクは、これまでどおり `mise prune` で外れる。

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
