# mise-skill: プロジェクト単位のリンク

- 日付: 2026-10-19
- 前提: `2026-10-16-mise-skill-plugin-design.md`（以下「初期設計」）。初期設計で対象外とした
  「リポジトリ内（プロジェクト単位）の `.claude/skills` / `.agents/skills` への配布」を扱う。
  初期設計の文書は変更しない。

## 背景

初期設計ではリンク先を `$HOME` 配下（`~/.claude/skills`、`~/.agents/skills`）に限っていた。
グローバルの mise config に書いたスキルはどのプロジェクトでも読まれる。プロジェクトでだけ
使いたいスキルは、プロジェクトの `mise.toml` に書き、そのプロジェクトの
`.claude/skills` / `.agents/skills` にリンクしたい。

## 目的

- プロジェクトの `mise.toml` に書いたスキルを、そのプロジェクトのエージェント用ディレクトリに
  リンクする。
- その `mise.toml` をリポジトリにコミットしてチームで共有できる（マシン固有のパスを書かない）。
  コミットせず自分だけで使うこともできる。
- エージェントの選び方（`agents` → `MISE_SKILL_AGENTS` → `claude-code`）はグローバルと同じ。
- 既存の設定の挙動は変えない。

## 対象外

- `dirs` の相対パスを `root` 基準で解釈すること。`dirs` は従来どおり絶対パスか `~/...` のみ。
- プロジェクトの設定からツールを消したときに、そのプロジェクトのリンクだけを外すこと
  （mise がその時点で呼ぶ hook が無い）。

## 使い方

```toml
# <project>/mise.toml
[tools]
"skill:example/writing-guide" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
```

`{{config_root}}` は mise がその設定ファイルのあるプロジェクトの絶対パスに展開する
（サブディレクトリから実行しても同じ）。プラグインは自分がどの設定ファイルに書かれたかを
知る手段を持たないため、利用者にこの 1 語を書いてもらう。

## オプション

| オプション | 既定 | 意味 |
|---|---|---|
| `root`（新規） | なし（`$HOME`） | `agents` のリンク先の基準ディレクトリ。絶対パスか `~/...` |

`skills` / `agents` / `dirs` は初期設計のまま。`dirs` は `root` の影響を受けない。

## リンク先の決定（`lib/targets.lua`）

- エージェントのディレクトリは `<基準>/.claude/skills`（claude-code）と
  `<基準>/.agents/skills`（codex）。基準は `root` があれば `root`、無ければ `$HOME`。
- `root` は `dirs` と同じ規則で展開する（`~` / `~/...` は `$HOME` 基準、`/` 始まりはそのまま）。
  それ以外はエラー: `mise-skill: root must be absolute or start with ~/: <値>`。

## リンクを張るタイミング

mise は同じ `tool@version` を 1 回しかインストールしない。BackendInstall はその 1 回しか
呼ばれないため、プロジェクト A で入れた版をプロジェクト B が流用すると、B にはリンクが
張られない。

BackendExecEnv でも BackendInstall と同じリンク処理を行う。ただし `root` を指定した設定のときだけ
行う。`root` が無い設定では、同じツールの別の版を指す 2 つの設定が同じ `$HOME` 配下のディレクトリに
リンクを張ろうとし、最後に ExecEnv が走った版へ共有のリンクが張り替わってしまう。そのため
`root` が無い設定は初期設計のまま、リンクを張るのは install のときだけにし、ExecEnv は何もせず
`{ env_vars = {} }` を返す。`root` があるとディレクトリはそのプロジェクトのものなので、
そこにリンクを張るのはそのプロジェクトの設定だけになる。mise 2026.10.11 で次を確認した。

- BackendExecEnv は、その版を使う設定ごとに、その設定の options（テンプレート展開済み）で
  呼ばれる。`mise install`（流用時も）、activate したシェルでプロジェクトに入ったとき
  （`mise hook-env`）、`mise env` / `mise exec` などで呼ばれる。
- mise は結果を install と options の組ごとにキャッシュする。実際に呼ばれるのは
  プロジェクトごと（options の組ごと）に 1 回。
- `mise install -f` は BackendUninstall → BackendInstall の順に呼び、その版のキャッシュを
  すべて捨てる。

`root` を指定して初めて入れるときは BackendInstall と BackendExecEnv の両方が呼ばれる。同じ版の
リンクは張り替えるだけなので結果は変わらない。

## 記録

1 つの版を複数のプロジェクトが共有するため、`install_path/.mise-skill.json` は上書きせず、
既存の一覧に追記する（重複は除く）。BackendUninstall は従来どおりこの記録を使うので、
`mise prune` / `mise uninstall` ですべてのプロジェクトのリンクが外れる。読めない記録は空として
扱い、上書きする。記録は一時ファイルに書いてから `os.rename` で置き換えるため、同時に読む側が
書きかけのファイルを見ることはない。2 つの書き込みが同時に走ると一方の更新が失われることは
ありうるが、その場合は prune がそのプロジェクトのリンクを外し損ねるだけで、宙に浮いたリンクは
あとで張り替えられる。

## 一時リンクの置き場

親ディレクトリが無いときの一時リンクは、初期設計では `download_path` に作っていた。
BackendExecEnv の ctx には `download_path` が無いため、リンク処理は一時リンクの置き場を
ディレクトリではなくパスで受け取る。

- BackendInstall: `<download_path>/mise-skill-link`
- BackendExecEnv: `os.tmpname()`（`/tmp` に書けなくても例外にならないよう pcall の中で呼ぶ）。このファイルは作成済みで返り、一時リンクを使わない場合は
  残るため、リンク処理の後（失敗しても）消す。

## エラー処理

| 場面 | 挙動 |
|---|---|
| BackendInstall でのオプションの誤り（相対パスの `root` など） | 従来どおりエラーにして install を失敗させる |
| BackendExecEnv での失敗（オプションの誤り、スキルの選択失敗、リンク失敗） | エラーにせず `mise-skill: could not link <tool>: <理由>` と警告して、`{ env_vars = {} }` を返す |

BackendExecEnv のエラーを mise は警告に落とすが、スタックトレース付きで出し、結果を
キャッシュしないため、毎回出てしまう。そのため警告にとどめる。

## 制約（README に記載する）

- プロジェクトの設定からツールを消しても、リンクはその版が prune されるまで残る。
- 手で消したリンクは、キャッシュが残る間は張り直されない。`mise cache clear` で張り直せる。
- 1 つのプロジェクトで `mise install -f` すると、ほかのプロジェクトのリンクも外れる。
  それぞれで次に mise が動いたときに張り直される。
- リンクはそのマシンの installs ディレクトリを指す。リポジトリでは
  `.claude/skills/<スキル名>` と `.agents/skills/<スキル名>` を gitignore する。
- activate したシェルでは、プロジェクトに入っただけでリンクが作られる。

## テスト

`tests/project.test.sh` を追加する。`tests/lib.sh` の `m()` は `wd` で実行ディレクトリを
変えられるようにする。

- プロジェクト a: `root = "{{config_root}}"`、`agents = ["claude-code", "codex"]` で install すると
  `a/.claude/skills` と `a/.agents/skills` にリンクができ、`~/.claude/skills` にはできない。
- プロジェクト b のサブディレクトリから同じ版を install（流用）すると b にリンクができ、
  a のリンクも残る。
- プロジェクト c で `mise hook-env` だけを実行してもリンクができる。
- `root` が相対パスだと、新規の install はエラーになる。流用時（`mise env`）は
  `mise-skill: could not link` の警告になり、スタックトレースは出ない。
- b で `mise install -f` した後、a で `mise env` を実行すると a のリンクが戻る。
- すべてのプロジェクトからツールを消して `mise prune` すると、すべてのリンクが外れる。
- `root` が無い設定では、古い版を固定したプロジェクトに入っても、グローバルのリンクは
  新しい版のまま変わらない（`mise cache clear` の後に `mise env` を実行して確かめる）。
- テストの前後で `/tmp/lua_*` が増えない。

## ドキュメント

- README / README.ja のオプション表に `root` を追加し、「プロジェクト単位」の節に使い方と
  上の制約を書く。
- 初期設計の文書は変更しない。
