# mise-skill: ユーザーとプロジェクトのスコープ

- 日付: 2026-10-23
- 前提: `2026-10-16-mise-skill-plugin-design.md`（以下「初期設計」）。初期設計のうち、リンクの
  張り方・外し方（「リンク（BackendInstall の後半）」「リンク解除（BackendUninstall）」と
  関連するオプション・エラー処理・テスト）をこの文書で置き換える。取得・スキルの発見・依存は
  初期設計のまま。
- PR #7（`root` オプション）は採らず、main からこの設計で作り直す。

## 背景

mise はツールをユーザー（グローバル設定）とプロジェクト（`mise.toml`）の両方で管理する。
初期設計はリンク先を `$HOME` 配下に限り、リンクを install の副作用にした。

mise のインストールは `tool@version` 単位で、すべての設定に共有される。一方、スキルをどこに
リンクするかは設定ファイル単位で決まる。ユーザースコープだけなら設定が実質 1 つなので
install の副作用で足りたが、プロジェクトを加えると合わない。同じ版を別のプロジェクトが
流用しても BackendInstall は呼ばれない。PR #7 はこのモデルのまま継ぎ足したため、
`install -f` で他プロジェクトのリンクが外れる、オプションの変更に `install -f` が要る、
などの制約が重なった。

この設計では、リンクの単位を「設定 × ツール」に改める。

## 目的

- グローバル設定に書いたスキルは `~/.claude/skills` などに、プロジェクトの `mise.toml` に
  書いたスキルはそのプロジェクトの `.claude/skills` などにリンクする。
- プロジェクトの `mise.toml` はコミットしてチームで共有できる（マシン固有のパスを書かない）。
- オプション（`skills` / `agents` / `dirs` / `root`）の変更は、`install -f` なしで反映する。
- プロジェクトの設定が古い版を固定しても、`~` のリンクはグローバル設定の版のまま変わらない。
- 利用者に hook やスクリプトの設定を求めない（初期設計のまま）。

## 対象外

- 利用者が何も書かずにプロジェクトを判定すること（「mise の制約」を参照）。
- 設定からツールを丸ごと消したときに、その設定のリンクだけを外すこと（呼ばれる hook が無い）。
- `dirs` の相対パス。`dirs` は初期設計どおり絶対パスか `~/...` のみ。

## 使い方

```toml
# ~/.config/mise/config.toml（ユーザー）
[tools]
"skill:example/writing-guide" = "latest"
```

```toml
# <project>/mise.toml（プロジェクト）
[tools]
"skill:example/prose-lint" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
```

`{{config_root}}` は mise がその設定ファイルのあるプロジェクトの絶対パスに展開する
（サブディレクトリから実行しても同じ）。

| やりたいこと | 操作 |
|---|---|
| 追加・版の更新 | `[tools]` を書いて `mise install`（`mise upgrade`） |
| `skills` / `agents` / `dirs` / `root` の変更を反映 | 何もしない（次に mise が動いたときに反映される） |
| 外したスキルのリンクを消す | `[tools]` から外して `mise prune` |

## mise の制約

2026-10-23、mise 2026.10.17 で使い捨てプラグインを動かして確認した。

- hook の ctx にも環境変数にも、ツールを宣言した設定ファイルの情報は無い。cwd は利用者の cwd。
- hook の中から `mise ls --current --json` を呼ぶと、各ツールの `source.path`（宣言した設定
  ファイル）が取れる。BackendInstall と BackendExecEnv のどちらからでも動く。
- BackendExecEnv の結果は「インストール × オプションの値」ごとにキャッシュされる
  （`$MISE_CACHE_DIR/<tool>/<version>/exec_env_<hash>`）。設定ファイルのパスはキーに含まれない。
  グローバルと 2 つのプロジェクトが同じ値（`"2.0.0"`）を書くと、ExecEnv は最初の 1 回しか
  呼ばれず、ほかの設定で `mise env` / `mise install` / `mise hook-env` を実行しても、どの hook も
  呼ばれない。
- 入れ済みの版をプロジェクトで `mise install` しても、どの hook も呼ばれない。
- mise は ExecEnv がエラーになった結果をキャッシュしない（PR #7 の調査、mise 2026.10.11）。

このため、プロジェクトごとに mise から呼ばれるには、プロジェクトごとに値が変わるオプションが
要る。`root = "{{config_root}}"` がその役を担う。値が固定のオプション（例: `scope = "project"`）
ではキャッシュキーが分かれないので代わりにならない。キャッシュを消して毎回呼ばせる方法は、
文書に無いキャッシュの配置に依存するため採らない。

## オプション

| オプション | 既定 | 意味 |
|---|---|---|
| `skills` | 見つかった全スキル | リンクするスキル名の一覧（初期設計のまま） |
| `agents` | `MISE_SKILL_AGENTS`（未設定なら `claude-code`） | リンク先をエージェント名で指定（初期設計のまま） |
| `dirs` | なし | リンク先をパスで追加指定（初期設計のまま。`root` の影響を受けない） |
| `root`（新規） | なし | エージェントのディレクトリの基準。絶対パスか `~/...`。プロジェクトでは `{{config_root}}` |

エージェントのディレクトリは `<基準>/.claude/skills`（claude-code）と `<基準>/.agents/skills`
（codex）。

## 基準ディレクトリの決定

- `root` があれば、それを `dirs` と同じ規則で展開して基準にする（`~` / `~/...` は `$HOME` 基準、
  `/` 始まりはそのまま）。それ以外はエラー:
  `mise-skill: root must be absolute or start with ~/: <値>`。
- `root` が無ければ `mise ls --current --json` を呼び、`install_path` が `ctx.install_path` と
  一致する項目の `source.path` を見る。ツール名ではなく `install_path` で照合するので、
  プラグインのインストール名（`skill:`）に依存しない。
  - `source.path` が mise のグローバル設定ディレクトリの下にあれば、`$HOME` を基準にする。
    グローバル設定ディレクトリは `MISE_CONFIG_DIR`、なければ `$XDG_CONFIG_HOME/mise`、なければ
    `~/.config/mise`。`mise config ls` にはグローバルかどうかの項目が無いため、パスで判定する。
  - それ以外（プロジェクトの設定）ならエラー:
    `mise-skill: <tool> is declared in <path> without root; add root = "{{config_root}}"`。
    警告にしてリンクしないだけだと、その結果がキャッシュされる。グローバルに同じオプションの
    値があると、グローバル側で ExecEnv が呼ばれなくなり `~` にリンクが張られない。エラーなら
    キャッシュされない。`root` の無いプロジェクトの設定はどこにもリンクしないので、設定の誤りと
    してうるさく知らせてよい。
  - `mise ls` が失敗した、または一致する項目が無い（例: `mise install skill:x@1` を引数だけで
    実行した）ときは、警告してリンクしない。

## リンク処理

BackendInstall と BackendExecEnv は同じリンク処理を呼ぶ。

1. 基準ディレクトリを決め、リンク先のディレクトリ（エージェントのディレクトリと `dirs`）を求める。
2. `skills` でスキルを選ぶ。リンクする各スキルのディレクトリに、所有の目印 `.mise-skill`
   （中身は `install_path`）を書く。
3. 各 `<dir>/<スキル名>` について、初期設計と同じ規則で扱う。
   - 何も無い、またはリンク切れ: この版のスキルへの symlink を作る。
   - 同じツールの本プラグインのリンク（目印の `install_path` の親が自分と同じ）: 張り替える。
   - それ以外（実ディレクトリ、他人のリンク、別の `skill:` ツールのリンク）: 触らず警告する。
4. 記録のうち、この基準の前回の一覧にあって今回張らなかったリンクを外す。外すのは、今もこの
   `install_path` を指しているものだけ。
5. 記録のこの基準の項目を、今回張ったリンクの一覧で置き換える。

| hook | 呼ぶ場面 | 失敗したとき |
|---|---|---|
| BackendInstall | 取得・展開の後 | エラーにして install を失敗させる（オプションの誤りや `root` の無いプロジェクトの設定に気づけるように）。個々のリンクの失敗は警告 |
| BackendExecEnv | 毎回 | `root` の無いプロジェクトの設定はエラー。そのほかは `mise-skill: could not link <tool>: <理由>` と警告して `{ env_vars = {} }` を返す |

ExecEnv のエラーを mise はスタックトレース付きで出し、キャッシュしないので毎回出る。そのため、
エラーにするのは上の 1 件だけにする。

初めて入れるときは BackendInstall と BackendExecEnv の両方が呼ばれる。同じ版のリンクは
張り替えるだけなので結果は変わらない。

### 一時リンクの置き場

親ディレクトリが無いときの一時リンクは、`download_path` ではなく `install_path` の中
（`<install_path>/.mise-skill-link`）に作る。ExecEnv の ctx には `download_path` が無いが
`install_path` はあり、必ず存在して書き込める。リンク先が別のファイルシステムで移動に失敗した
ときの扱い（親は作られているので、同じディレクトリでの作成に切り替える）は初期設計のまま。

## 記録

`install_path/.mise-skill.json` は「基準ディレクトリ → その設定で張ったリンクの一覧」の表にする。

```json
{
  "/home/u": ["/home/u/.claude/skills/alpha", "/home/u/somewhere/skills/alpha"],
  "/home/u/dev/p1": ["/home/u/dev/p1/.claude/skills/alpha", "/home/u/dev/p1/.agents/skills/alpha"]
}
```

- `dirs` のリンクは、それを張った設定の基準の項目に入れる。
- リンク処理は自分の基準の項目だけを入れ替え、ほかの項目は残す。
- 読めない記録や、配列の形の記録（初期設計の形式）は空として扱う。初期設計の形式で記録された
  リンクは、次の ExecEnv で同じリンクが記録し直されるため、移行の処理は設けない。
- 書き込みは一時ファイルに書いてから `os.rename` で置き換える。同時に 2 つ書くと一方の更新が
  失われうるが、その場合は prune でそのリンクを外し損ねるだけで、残ったリンクはあとで
  張り替えられる。

## リンク解除（BackendUninstall）

記録のすべての基準のリンクのうち、今もこの `install_path` を指しているものだけを `os.remove` で
消す（初期設計と同じ一致確認）。`mise prune` / `mise uninstall` で全 root のリンクが外れる。

`mise install -f` は BackendUninstall を呼んでから入れ直し、その版のキャッシュをすべて捨てる。
そのため、ほかのプロジェクトのリンクも一度外れ、それぞれで次に mise が動いたときに戻る。

## 制約（README に記載する）

- 設定からツールを丸ごと消しても、リンクはその版が prune されるまで残る。
- 手で消したリンクは、キャッシュが残る間は張り直されない。`mise cache clear` で張り直せる。
- 1 つのプロジェクトで `mise install -f` すると、ほかのプロジェクトのリンクも一度外れる。
- 2 つの設定が同じツールの違う版を同じ `dirs` に向けると、mise が動くたびに張り替わる。
- リンクはそのマシンの installs ディレクトリを指す。プロジェクトでは `.claude/skills/<スキル名>` と
  `.agents/skills/<スキル名>` を gitignore する。
- activate したシェルでは、プロジェクトに入っただけでリンクが作られる。

## エラー処理

| 状況 | 動き |
|---|---|
| `skills` に無い名前、未知の `agents`、相対パスの `root` / `dirs` | install を失敗させる。ExecEnv では警告 |
| `root` の無いプロジェクトの設定 | install も ExecEnv もエラー |
| `mise ls` の失敗、一致する項目が無い | 警告してリンクしない |
| 実ディレクトリ・他人のリンク・別の `skill:` ツールのリンクと衝突 | 触らず警告する |
| 個々のリンクの作成・削除の失敗 | 警告する |
| 取得・展開・`SKILL.md` に関する失敗 | 初期設計のまま |

## テスト

fixture（`bright-room-sandbox/mise-skill-fixtures`）は今のまま使う。`tests/lib.sh` の `m()` は
実行ディレクトリを変えられるようにする。CI は従来どおり Linux と macOS で回す。

- `tests/link.test.sh`（グローバル）: 今の項目を残し、「オプションの変更が `install -f` で反映
  されること」を「`mise env` だけで反映されること（`skills` を減らすとリンクが外れる）」に
  置き換える。
- `tests/project.test.sh`（新規）
  - `root = "{{config_root}}"` のプロジェクトで install すると、そのプロジェクトにリンクができ、
    `~` にはできない。
  - 入れ済みの版を別のプロジェクトのサブディレクトリから使うとそこにリンクができ、前のプロジェクトの
    リンクも残る。`mise hook-env` だけでもできる。
  - `root` の無いプロジェクトの設定は install も `mise env` もエラーになる。その後、同じ値の
    グローバル設定で `mise env` を実行すると `~` にリンクができる（キャッシュに残らないこと）。
  - プロジェクトが古い版を固定しても、`~` のリンクはグローバルの版のまま変わらない。
  - プロジェクトで `skills` を変えると、そのプロジェクトのリンクだけが変わる。
  - 1 つのプロジェクトで `install -f` した後、ほかのプロジェクトで `mise env` を実行すると、
    そこのリンクが戻る。
  - すべての設定からツールを消して `mise prune` すると、すべての root のリンクが外れる。
  - 相対パスの `root` は install でエラー、`mise env` では警告（スタックトレースは出ない）になる。

## 文書

- README / README.ja: オプション表に `root` を足し、「スコープ」の節に使い方と上の制約を書く。
  「リンクを最新に保つ」の表から `install -f` でオプション変更を反映する行を外す。
- 初期設計の文書の冒頭に、リンクの節をこの文書で置き換えたことを 1 行で記す。
