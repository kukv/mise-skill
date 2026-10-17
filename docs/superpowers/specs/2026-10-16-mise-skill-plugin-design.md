# mise-skill: エージェントスキルを mise で管理する backend plugin

- 日付: 2026-10-16
- リポジトリ: `kukv/mise-skill`（公開。作成は `kukv/structure` の Terraform で行う）
- 作業ディレクトリ: `~/dev/workspaces/mise-skill`（リポジトリ作成まで）

## 背景

dotfiles は Claude Code のスキルを skills CLI（`npm:skills`）で入れ、一覧を
`bootstrap/post-tools.sh` のヒアドキュメントで管理している。mise 本体の
`mise skills` は `packslip:` backend のツールが署名付き manifest で宣言したスキルしか
扱えないため、SKILL.md を置いただけの普通のリポジトリ（例: `example/writing-guide`）は
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
"skill:example/writing-guide" = "latest"
"skill:example/prose-lint" = { version = "latest", agents = ["claude-code"] }
"skill:example/code-search" = { version = "ref:main", skills = ["code-search", "code-search-outline"] }
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
  版らしくないタグ（`v` の後が数字で始まらないもの。例: `draft-v9`）は除く。
  版が 1 つも無ければ `ref:` の使用を案内して失敗する（`ref:` の版ではこの hook は呼ばれない）。
- **BackendInstall**: 指定版（タグ、または `ref:` で渡された ref）の tarball を
  `codeload.github.com` から取得し、`install_path` に展開する。展開後に `SKILL.md` が
  1 つも無ければ失敗させる。タグは `v` 付き・無しの両方を試して解決する。
  続けてリンクを張る（後述）。
- **BackendExecEnv**: `{ env_vars = {} }` を返す（PATH を変えない）。
- GitHub のトークンは扱わない。mise の `http` は `api.github.com` 宛てに mise が解決した
  トークンを自動で付ける。`codeload.github.com` 宛てには付けない（付けると失敗する）。

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
（自作の symlink を置いて確認した）。Codex は公式ドキュメントに
「supports symlinked skill folders」とあり、利用者用の置き場は `~/.agents/skills`。

### リンク（BackendInstall の後半）

1. `ctx.options` から対象スキルとリンク先ディレクトリを決める。
2. リンクする各スキルディレクトリに、所有の目印 `.mise-skill`（中身は `install_path`）を書く。
3. 各 `<dir>/<スキル名>` について:
   - 何も無ければ、この版のスキルディレクトリへの symlink を作る。
   - 同じツールの本プラグインのリンク（後述）なら張り替える。版の更新はここで追従する。
     同じツールかどうかは、目印の `install_path` と自分の `install_path` の親ディレクトリが
     同じかで判定する。
   - それ以外（実ディレクトリ・他人のリンク・別のツールが張ったリンク）なら触らず、
     警告して skipped とする。
4. 張ったリンクの一覧を `install_path/.mise-skill.json` に記録する。

symlink はリンク先と同じディレクトリに一時的な名前で作り、`file.move`（rename）で
置き換える。同じディレクトリ内なので rename がファイルシステムをまたがない。
親ディレクトリが無いときだけ、`download_path` に作ってから `file.move` で移す。`file.symlink` は
親ディレクトリが無いと失敗するが、`file.move` は親を作るため。リンク先が別のファイルシステムで
この移動が失敗しても、その時点で親は作られているので、同じディレクトリでの作成に切り替える。

**本プラグインのリンク**: symlink で、リンク越しに `.mise-skill` が読めるもの。
`file.stat` はリンク先を返さない（readlink 相当が無い）ため、目印ファイルで判定する。
目印の中身で、どの版の `install_path` を指しているかも分かる。

### リンク解除（BackendUninstall）

`install_path/.mise-skill.json` に記録したリンクのうち、今もこの `install_path` を
指しているもの（リンク越しの `.mise-skill` の中身が一致するもの）だけを `os.remove` で消す。
`mise prune` 時の `ctx.options` は既定値しか持たないため、オプションではなく記録を使う。

`mise upgrade` は新しい版を入れたあと、古い版をすぐには消さない（後の prune や遅延削除で
消える）。そのときに新しい版のリンクを消さないよう、この一致確認が要る。
`mise install -f` は先に BackendUninstall を呼んでから入れ直すため、オプション変更で
外れたリンクもここで消える。

### 依存

追加のツールを要求しない。処理はすべて mise 内蔵の Lua モジュールで行う。

| 処理 | 使うもの |
|---|---|
| GitHub API・tarball の取得 | `http` |
| API 応答と記録ファイルの読み書き | `json` |
| tarball の展開 | `archiver.decompress`（`.tar.gz` 対応） |
| `SKILL.md` の探索 | `file.glob`（`**` が使え、直下の `SKILL.md` にも一致する） |
| リンクの作成・判定 | `file.symlink` + `file.move` / `file.stat`（`is_symlink`） / `file.read` |
| リンクの削除 | Lua 標準の `os.remove`（symlink 自体を消す） |

`metadata.lua` の `depends` / `systemDependencies` は使わない。

## エラー処理

| 状況 | 動き |
|---|---|
| タグが無いリポジトリで `latest` | install を失敗させ、`ref:<branch>` の使用を案内する |
| 取得物に `SKILL.md` が無い | install を失敗させる |
| `skills` に書いた名前が無い | install を失敗させる（綴り間違いに気づけるように） |
| 同じリポジトリ内に同名スキルが複数 | install を失敗させる |
| 実ディレクトリ・他人のリンクと衝突 | 触らず警告し、install は成功させる |
| 別の `skill:` ツールのリンクと衝突（同名スキル） | 触らず警告し、install は成功させる（先に入れた方が残る） |
| 同名のリンク切れ symlink がある | 置き換える（誰の役にも立っておらず、install ディレクトリを手で消した本プラグインのリンクもこうなる） |
| install が途中で失敗 | 次の `mise install` で入れ直せること（入れ済み扱いで飛ばされないこと）をテストで確かめる |
| `agents` に未知の名前 | install を失敗させる |

## テスト

dotfiles の `tests/bootstrap/*.test.sh` と同じく素の sh で書き、使い捨ての
`HOME` / `MISE_DATA_DIR` で実行する。

- テストの対象は実在のスキルではなく、自前の fixture リポジトリ `bright-room-sandbox/mise-skill-fixtures` にする。
  タグ `v0.1.0` / `v0.2.0`（版でないタグ `draft-v9` も混ぜる）、スキル `alpha` `beta` `gamma`、
  ブランチ `no-skills`（`SKILL.md` 無し）、`invalid-name`（不正な名前のスキル入り）を置く。
  タグ無しのリポジトリには fixture の `bright-room-sandbox/mise-skill-fixtures-untagged` を使う。
- `tests/install.test.sh`: `mise plugins link` で実際に入れる。
  - fixture のタグ指定（`@0.1.0`）と `ref:`（`ref:invalid-name`）
  - `ref:no-skills` で `SKILL.md` 無しとして失敗すること
  - タグ無しの `bright-room-sandbox/mise-skill-fixtures-untagged` で `latest` を指定したときに失敗すること
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

`kukv/structure` で `terraform/repository_mise_skill.tf` を追加する PR を出す。
手順と指定できる引数は structure の `manage-repository` スキルと
`terraform/modules/repository/variables.tf` に従う。apply は structure の PR マージで行う。
作成後、`~/dev/workspaces/mise-skill` の内容を push する。

## dotfiles への移行（プラグインのリリース後、別 PR）

1. mise config にプラグイン、`skill:*` のツール、`MISE_SKILL_AGENTS` を追加する。
2. `bootstrap/post-tools.sh` のスキル用ループと、mise config の `npm:skills` を削除する。
3. 移行手順: skills CLI で入れた実ディレクトリ（`~/.claude/skills/*`、`~/.agents/skills/*`）と
   `~/.agents/.skill-lock.json` を消してから `mise install -f` でスキルを入れ直す。
   自作スキルのディレクトリと自作 symlink は対象外で触らない。
4. メモリ `claude-skills-provisioning` を新方式に書き換える。

## 確認済みの前提（2026-10-16、mise 2026.10.10 で使い捨てプラグインを動かして確認）

| 項目 | 結果 |
|---|---|
| `"ref:main"` の渡り方 | `ctx.version = "ref:main"`、`install_path` は `.../ref-main`。BackendListVersions は呼ばれない |
| 版を指定した install | BackendListVersions が呼ばれ、そのエラーで install が止まる |
| 配列のオプション | `ctx.options.skills` などは Lua の配列のまま届く |
| `[env]` の値 | `os.getenv("MISE_SKILL_AGENTS")` で読める |
| installs ディレクトリ名 | `skill-<owner>-<repo>`（実装はこの名前に依存しない） |
| 親が無い場所への `file.symlink` | 失敗する（No such file or directory） |
| `download_path` に作った symlink を `file.move` | 親ディレクトリを作って移動でき、symlink のまま |
| `os.remove` | symlink 自体を消す |
| `mise prune` | 各版の BackendUninstall を `install_path` 付きで呼ぶ |
| `mise install -f` | BackendUninstall を呼んでから BackendInstall を呼ぶ |
| `mise upgrade` | 新しい版を入れ、古い版の BackendUninstall はその場では呼ばない |
| `file.glob("<dir>/**/SKILL.md")` | 直下とサブディレクトリの両方に一致する |
