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

- スキルを mise config の `[tools]` に宣言し、`mise install` だけで使える状態にする。
- 取得したスキルを、エージェントが読むディレクトリへ symlink で配る。
- 版を固定・更新できるようにする（タグ、またはブランチ・コミット）。
- 利用者に hook やスクリプトの設定を求めない。

## 対象外

- リポジトリ内（プロジェクト単位）の `.claude/skills` / `.agents/skills` への配布。
  グローバル（`$HOME` 配下）のみを扱う。
- GitHub 以外のホスト。
- 署名・検証（packslip が担う領域）。
- Windows。

## 使い方

```toml
[env]
MISE_SKILL_AGENTS = "claude-code,codex"   # 全体の既定。未設定なら claude-code

[tools]
"skill:coji/natural-japanese" = "latest"
"skill:nanaism/yomiyasu" = { version = "latest", agents = ["claude-code"] }
"skill:ast-grep/agent-skill" = { version = "ref:main", skills = ["ast-grep", "ast-grep-outline"] }
"skill:foo/bar" = { version = "latest", dirs = ["~/somewhere/skills"] }
```

プラグインは `mise plugins install skill https://github.com/kukv/mise-skill` で入れる。
プレフィックス `skill:` はこのインストール名から決まる。

| やりたいこと | 操作 |
|---|---|
| 追加・版の更新 | `[tools]` を書いて `mise install`（`mise upgrade`） |
| `skills` / `agents` / `dirs` の変更を反映 | `mise install -f skill:owner/repo` |
| 外したスキルのリンクを消す | `[tools]` から外して `mise prune` |

リンクは install / uninstall のときにしか張り替えないため、入れ済みの版の設定変更は
`install -f` が要る。これは「hook の設定を不要にする」ことと引き換えに受け入れた制約。

## 構成

```
mise-skill/
├── metadata.lua
├── hooks/
│   ├── backend_list_versions.lua
│   ├── backend_install.lua
│   ├── backend_uninstall.lua
│   └── backend_exec_env.lua
├── lib/                 # GitHub 取得、スキル発見、リンク処理
└── tests/
    ├── install.test.sh
    └── link.test.sh
```

### 取得

- `ctx.tool` は `owner/repo`。
- **BackendListVersions**: GitHub API でタグ一覧を取り、先頭の `v` を除いた版を古い順に返す。
  タグが無ければ空を返す。
- **BackendInstall**: 指定版（タグ、または `ref:` で渡された ref）の tarball を
  `codeload.github.com` から取得し、`install_path` に展開する。展開後に `SKILL.md` が
  1 つも無ければ失敗させる。タグは `v` 付き・無しの両方を試して解決する。
  続けてリンクを張る（後述）。
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

エージェント名と実際のディレクトリの対応はプラグインに内蔵する。

| agent | ディレクトリ |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

Claude Code が symlink のスキルを読むことは手元で確認済み
（`~/.claude/skills/koto-import` は symlink）。Codex は公式ドキュメントに
「supports symlinked skill folders」とあり、利用者用の置き場は `~/.agents/skills`。

### リンク（BackendInstall の後半）

1. `ctx.options` から対象スキルとリンク先ディレクトリを決める。
2. 各 `<dir>/<スキル名>` について:
   - 何も無ければ、この版のスキルディレクトリへの symlink を作る（`<dir>` が無ければ作る）。
   - 本プラグインのリンク（後述）なら張り替える。版の更新はここで追従する。
   - それ以外（実ディレクトリ・他人のリンク）なら触らず、警告して skipped とする。
3. 張ったリンクの一覧を `install_path/.mise-skill.json` に記録する。

**本プラグインのリンク**: symlink で、リンク先の祖先ディレクトリに `.mise-skill.json` が
あるもの。installs ディレクトリの命名に依存しない。

### リンク解除（BackendUninstall）

`install_path/.mise-skill.json` に記録したリンクのうち、今もこの `install_path` を
指しているものだけを消す。`mise prune` 時の `ctx.options` は既定値しか持たないため、
オプションではなく記録を使う。新しい版に張り替え済みのリンクは消えない。

### 依存

追加のツールを要求しない。処理はすべて mise 内蔵の Lua モジュールで行う。

| 処理 | 使うもの |
|---|---|
| GitHub API・tarball の取得 | `http` |
| API 応答と記録ファイルの読み書き | `json` |
| tarball の展開 | `archiver.decompress`（`.tar.gz` 対応） |
| `SKILL.md` の探索 | `file.glob` / `file.list` |
| リンクの作成・判定 | `file.symlink` / `file.stat`（`is_symlink`） |
| リンクの削除 | Lua 標準の `os.remove` |

`metadata.lua` の `depends` / `systemDependencies` は使わない。

## エラー処理

| 状況 | 動き |
|---|---|
| タグが無いリポジトリで `latest` | install を失敗させ、`ref:<branch>` の使用を案内する |
| 取得物に `SKILL.md` が無い | install を失敗させる |
| `skills` に書いた名前が無い | install を失敗させる（綴り間違いに気づけるように） |
| 同じリポジトリ内に同名スキルが複数 | install を失敗させる |
| 実ディレクトリ・他人のリンクと衝突 | 触らず警告し、install は成功させる |
| `agents` に未知の名前 | install を失敗させる |

## テスト

dotfiles の `tests/bootstrap/*.test.sh` と同じく素の sh で書き、使い捨ての
`HOME` / `MISE_DATA_DIR` で実行する。

- `tests/install.test.sh`: `mise plugins link` で実際に入れる。
  - `coji/natural-japanese`（タグあり、`latest` と版固定）
  - `ast-grep/agent-skill`（タグ無し、`ref:main`）
  - `nanaism/yomiyasu`
  - タグ無しで `latest` を指定したときに失敗すること
  - `skills` に無い名前・未知の `agents` で失敗すること
- `tests/link.test.sh`:
  - install でリンクが張られること、版の更新で張り替わること
  - 古い版の uninstall で新しい版のリンクが消えないこと
  - `[tools]` から外して `mise prune` するとリンクが消えること
  - 実ディレクトリとの衝突で skipped になり、中身が変わらないこと
  - `skills` による絞り込み、`agents` / `dirs` / `MISE_SKILL_AGENTS` の組み合わせ
  - オプション変更が `install -f` で反映されること
- GitHub Actions で Linux と macOS の両方で回す。

## リポジトリの作成

`kukv/structure` で `terraform/repository_mise-skill.tf` を追加する PR を出す。
手順と指定できる引数は structure の `manage-repository` スキルと
`terraform/modules/repository/variables.tf` に従う。apply は structure の PR マージで行う。
作成後、`~/dev/workspaces/mise-skill` の内容を push する。

## dotfiles への移行（プラグインのリリース後、別 PR）

1. mise config にプラグイン、`skill:*` のツール、`MISE_SKILL_AGENTS` を追加する。
2. `bootstrap/post-tools.sh` のスキル用ループと、mise config の `npm:skills` を削除する。
3. 移行手順: skills CLI で入れた実ディレクトリ（`~/.claude/skills/*`、`~/.agents/skills/*`）と
   `~/.agents/.skill-lock.json` を消してから `mise install -f` でスキルを入れ直す。
   `hunk-review`（自作ローダー）と `koto-import`（自前 symlink）は対象外で触らない。
4. メモリ `claude-skills-provisioning` を新方式に書き換える。

## 実装前に確かめること

最初のタスクで小さく試し、結果に応じて設計を直す。

1. `"skill:owner/repo" = "ref:main"` が backend plugin の hook にどう渡るか（`ctx.version` の値）。
2. BackendInstall の `ctx.options` に `skills` / `agents` / `dirs` が配列のまま届くか
   （ドキュメント上、値は文字列に変換されることがある）。
3. `mise prune` / `mise uninstall` で BackendUninstall が呼ばれ、`ctx.install_path` が渡るか。
4. mise の Lua 環境で `os.remove` が使え、symlink 自体（リンク先ではなく）を消せるか。
5. リンク先ディレクトリ（例: `~/.agents/skills`）が無いとき、内蔵モジュールだけで作れるか。
   `file` モジュールに mkdir が無いため、`file.symlink` が親を作るか、別の手段が要るかを確かめる。
   内蔵で作れなければ、ディレクトリが無いエージェントはスキップして警告する
   （そのエージェントが入っていない、と見なす）。

`[env]` の値が hook から `os.getenv` で読めることは、ドキュメント（hook environment）で確認済み。
