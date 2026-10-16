# mise-skill: エージェントスキルを mise で管理する backend plugin

- 日付: 2026-10-16
- リポジトリ: `kukv/mise-skill`（公開。作成は `kukv/structure` の Terraform で行う）
- 作業ディレクトリ: `~/dev/workspaces/mise-skill`（リポジトリ作成まで）

## 背景

dotfiles は Claude Code のスキルを skills CLI（`npm:skills`）で入れ、一覧を
`bootstrap/post-tools.sh` のヒアドキュメントで管理している。mise 本体の
`mise skills` は `packslip:` backend のツールが署名付き manifest で宣言したスキルしか
扱えないため、SKILL.md を置いただけの普通のリポジトリ（例: `coji/natural-japanese`）は
mise で管理できない。既存のプラグインも見当たらない。

## 目的

- スキルを mise config の `[tools]` に宣言し、`mise install` で取得できるようにする。
- 取得したスキルを、エージェントが読むディレクトリへ symlink で配る。
- 版を固定・更新できるようにする（タグ、またはブランチ・コミット）。

## 対象外

- リポジトリ内（プロジェクト単位）の `.claude/skills` / `.agents/skills` への配布。
  グローバル（`$HOME` 配下）のみを扱う。
- GitHub 以外のホスト。
- 署名・検証（packslip が担う領域）。

## 使い方

```toml
[env]
MISE_SKILL_AGENTS = "claude-code,codex"   # 全体の既定。未設定なら claude-code

[tools]
"skill:coji/natural-japanese" = "latest"
"skill:nanaism/yomiyasu" = { version = "latest", agents = ["claude-code"] }
"skill:ast-grep/agent-skill" = { version = "ref:main", skills = ["ast-grep", "ast-grep-outline"] }
"skill:foo/bar" = { version = "latest", dirs = ["~/somewhere/skills"] }

[hooks]
postinstall = "~/.local/share/mise/plugins/skill/bin/sync"
```

プラグインは `mise plugins install skill https://github.com/kukv/mise-skill` で入れる。
プレフィックス `skill:` はこのインストール名から決まる。

## 構成

```
mise-skill/
├── metadata.lua
├── hooks/
│   ├── backend_list_versions.lua
│   ├── backend_install.lua
│   └── backend_exec_env.lua
├── bin/sync
└── tests/
    ├── install.test.sh
    └── sync.test.sh
```

取得（backend plugin）とリンク（`bin/sync`）は分離する。backend plugin は mise に
サブコマンドを追加できないため、sync は同梱スクリプトとして配り、利用者が
`[hooks] postinstall` から呼ぶ。手動実行もできる。

### backend plugin

- `ctx.tool` は `owner/repo`。
- **BackendListVersions**: GitHub API でタグ一覧を取り、先頭の `v` を除いた版を古い順に返す。
  タグが無ければ空を返す。
- **BackendInstall**: 指定版（タグ、または `ref:` で渡された ref）の tarball を
  `codeload.github.com` から取得し、`install_path` に展開する。展開後に `SKILL.md` が
  1 つも無ければ失敗させる。タグは `v` 付き・無しの両方を試して解決する。
- **BackendExecEnv**: `{ env_vars = {} }` を返す（PATH を変えない）。
- GitHub API には `MISE_GITHUB_TOKEN` / `GITHUB_TOKEN` があれば付ける。

### スキルの発見

`install_path` 以下の `SKILL.md` を再帰的に探し、frontmatter の `name:` をスキル名、
`SKILL.md` を含むディレクトリをスキルの実体とする（skills CLI の `--skill` と同じ名前になる）。

### ツールオプション

| オプション | 既定 | 意味 |
|---|---|---|
| `skills` | 見つかった全スキル | リンクするスキル名の一覧 |
| `agents` | `MISE_SKILL_AGENTS`（未設定なら `claude-code`） | リンク先をエージェント名で指定 |
| `dirs` | なし | リンク先をパスで追加指定。`agents` と併用すると両方に張る |

エージェント名と実際のディレクトリの対応は sync に内蔵する。

| agent | ディレクトリ |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

Claude Code が symlink のスキルを読むことは手元で確認済み
（`~/.claude/skills/koto-import` は symlink）。Codex は公式ドキュメントに
「supports symlinked skill folders」とあり、利用者用の置き場は `~/.agents/skills`。

### sync

1. `mise ls --current --json` で `skill:` で始まるツールの有効な版と `install_path` を得る。
2. ツールごとに `mise tool <name> --json` の `tool_options` から `skills` / `agents` / `dirs` を読む。
3. 各リンク先 `<dir>/<skill名>` に、有効な版のスキルディレクトリへの symlink を張る。
   既に自分のリンクがあり、指す先が違えば張り替える。
4. 自分のリンクのうち、今回の対象に無いもの・リンク切れのものを削除する。

「自分のリンク」は、リンク先が mise の installs 配下の本プラグインのディレクトリを指す
symlink と定義する。台帳ファイルは持たない。

依存: POSIX sh、`jq`、`mise`。

## エラー処理

| 状況 | 動き |
|---|---|
| タグが無いリポジトリで `latest` | install を失敗させ、`ref:<branch>` の使用を案内する |
| 取得物に `SKILL.md` が無い | install を失敗させる |
| `skills` に書いた名前が無い | sync が警告し、残りは続ける |
| 同じ dir に同名スキルが複数 | 先に処理したものを採用し、後のものは skipped と報告する |
| 実ディレクトリ・他人のリンクと衝突 | 触らず skipped と報告する |
| `agents` に未知の名前 | 警告して無視する |
| `jq` が無い | sync を即座に失敗させる |

sync はスキル単位の失敗で止めず、最後にまとめて報告する。失敗が 1 つでもあれば
終了コードを非 0 にする。

## テスト

dotfiles の `tests/bootstrap/*.test.sh` と同じく素の sh で書き、使い捨ての
`HOME` / `MISE_DATA_DIR` で実行する。

- `tests/install.test.sh`: `mise plugins link` で実際に入れる。
  - `coji/natural-japanese`（タグあり、`latest` と版固定）
  - `ast-grep/agent-skill`（タグ無し、`ref:main`）
  - `nanaism/yomiyasu`
  - タグ無しで `latest` を指定したときに失敗すること
- `tests/sync.test.sh`:
  - リンクの作成、版変更での張り替え、設定から外したときの削除、リンク切れの削除
  - 実ディレクトリとの衝突で skipped になること
  - `skills` による絞り込み、`agents` / `dirs` / `MISE_SKILL_AGENTS` の組み合わせ
- GitHub Actions で Linux と macOS の両方で回す。

## リポジトリの作成

`kukv/structure` で `terraform/repository_mise-skill.tf` を追加する PR を出す。
手順と指定できる引数は structure の `manage-repository` スキルと
`terraform/modules/repository/variables.tf` に従う。apply は structure の PR マージで行う。
作成後、`~/dev/workspaces/mise-skill` の内容を push する。

## dotfiles への移行（プラグインのリリース後、別 PR）

1. mise config にプラグイン、`skill:*` のツール、`MISE_SKILL_AGENTS`、`[hooks] postinstall` を追加する。
2. `bootstrap/post-tools.sh` のスキル用ループと、mise config の `npm:skills` を削除する。
3. 移行手順: skills CLI で入れた実ディレクトリ（`~/.claude/skills/*`、`~/.agents/skills/*`）と
   `~/.agents/.skill-lock.json` を消してから sync を回す。`hunk-review`（自作ローダー）と
   `koto-import`（自前 symlink）は対象外で触らない。
4. メモリ `claude-skills-provisioning` を新方式に書き換える。

## 実装前に確かめること

最初のタスクで小さく試し、結果に応じて設計を直す。

1. `"skill:owner/repo" = "ref:main"` が backend plugin の hook にどう渡るか（`ctx.version` の値）。
2. installs ディレクトリの実際の名前（「自分のリンク」の判定に使う）。
3. グローバル設定の `[hooks] postinstall` が `mise install`（グローバルのツール）でも発火するか。
4. `mise tool skill:owner/repo --json` の `tool_options` に `skills` などの独自オプションが出るか。
