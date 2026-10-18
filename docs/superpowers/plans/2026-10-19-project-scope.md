# Project Scope Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** プロジェクトの `mise.toml` に `root = "{{config_root}}"` と書いたスキルを、そのプロジェクトの `.claude/skills` / `.agents/skills` にリンクする。別のプロジェクトで入れた版を流用するときもリンクする。

**Architecture:** `lib/targets.lua` に `root` オプションを足し、エージェントのリンク先の基準を `$HOME` から切り替えられるようにする。版ごとに 1 回しか呼ばれない BackendInstall に加えて、設定ごとに呼ばれる BackendExecEnv でも同じリンク処理を行う。1 つの版を複数のプロジェクトが共有するので、`lib/links.lua` のリンク記録を上書きから追記に変える。

**Tech Stack:** Lua 5.1（mise 内蔵ランタイム、内蔵モジュール `file` `json` `log` と標準ライブラリ）、テストは POSIX sh + 実物の mise。

**Spec:** `docs/superpowers/specs/2026-10-19-project-scope-design.md`（前提: `docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md`）

## Global Constraints

- 初期設計の spec（`docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md`）と初期の plan は変更しない。
- 新しいオプションは `root` の 1 つだけ。既定は無し（`$HOME` 基準）。絶対パスか `~/...`。それ以外のエラーは `mise-skill: root must be absolute or start with ~/: <値>`。
- `dirs` は `root` の影響を受けない。`dirs` のエラーメッセージ（`mise-skill: dirs entries must be absolute or start with ~/: <値>`）は変えない。
- エージェント対応表: `claude-code` → `<基準>/.claude/skills`、`codex` → `<基準>/.agents/skills`。
- BackendExecEnv はエラーを投げない。失敗は `mise-skill: could not link <tool>: <理由>` の警告にして `{ env_vars = {} }` を返す。
- `cmd.exec` / `os.execute` / `io.popen` は使わない。
- エラーメッセージ・警告は `mise-skill: ` で始める。
- テストは `mise run ci`（lint + 全テスト）で確認する。テストは GitHub の fixture リポジトリ `bright-room-sandbox/mise-skill-fixtures` を使い、gh CLI のログインか `GITHUB_TOKEN` が必要。
- コミットメッセージは日本語で `feat:` / `docs:` などの接頭辞を付け、末尾に `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` を付ける。

## File Structure

| ファイル | 変更 | 責務 |
|---|---|---|
| `lib/targets.lua` | 変更 | `root` を読み、エージェントのリンク先の基準を決める |
| `lib/links.lua` | 変更 | 一時リンクの置き場をパスで受け取る。記録を追記にする |
| `hooks/backend_install.lua` | 変更 | 一時リンクのパスを渡す |
| `hooks/backend_exec_env.lua` | 変更 | 流用時もリンクを張る。失敗は警告だけ |
| `tests/lib.sh` | 変更 | `m()` を `wd` で実行ディレクトリを変えられるようにする |
| `tests/project.test.sh` | 新規 | プロジェクト単位のテスト |
| `README.md` / `README.ja.md` | 変更 | `root` オプションとプロジェクト単位の節 |

---

### Task 1: `root` オプション

新規インストールで、プロジェクトのディレクトリにリンクできるようにする。流用時のリンクは Task 2 で扱う。

**Files:**
- Modify: `lib/targets.lua`
- Modify: `tests/lib.sh:15-20`
- Create: `tests/project.test.sh`

**Interfaces:**
- Consumes: なし
- Produces: `targets.resolve(options, env_agents, home) -> string[]`（シグネチャは変えない。`options.root` を読むようになる）。`tests/lib.sh` の `m()` は環境変数 `wd` があればそこで mise を実行する。

- [ ] **Step 1: `tests/lib.sh` の `m()` を `wd` 対応にする**

`tests/lib.sh` の次の部分を:

```sh
# m <args...>: run mise inside $h with no XDG / MISE_* overrides leaking in from the caller.
m() {
  (cd "$h/work" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
```

次のように変える（3 行目の `env` 以降は変えない）:

```sh
# m <args...>: run mise inside $h (in $wd if set, else $h/work) with no XDG / MISE_* overrides
# leaking in from the caller.
m() {
  (cd "${wd:-$h/work}" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
```

呼び出し側は `wd="$h/work/a" m install` のように書く。

- [ ] **Step 2: 失敗するテストを書く**

`tests/project.test.sh` を作る:

```sh
#!/bin/sh
# Project scope: root = "{{config_root}}" links into the agents' directories of each project that
# uses the tool.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
fx=skill:bright-room-sandbox/mise-skill-fixtures

new_home project
echo '[tools]' | config
for p in a b c; do
  mkdir -p "$h/work/$p/sub"
  printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}", agents = ["claude-code", "codex"] }\n' \
    "$fx" > "$h/work/$p/mise.toml"
done

# the first project installs the version and is linked for both agents
wd="$h/work/a" m install >/dev/null 2>&1 || fail "a: install"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "a: claude-code link"
[ -f "$h/work/a/.agents/skills/alpha/SKILL.md" ] || fail "a: codex link"
[ -e "$h/.claude/skills/alpha" ] && fail "a: root should replace ~ for the agents"

# a relative root fails a fresh install
new_home bad-root
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad-root: install should fail"; fi
echo "$err" | grep -q 'root must be absolute or start with ~/: relative' ||
  fail "bad-root: error should name root, got: $err"

echo "ok project"
```

- [ ] **Step 3: テストが失敗することを確認する**

Run: `sh tests/project.test.sh`
Expected: `FAIL: a: claude-code link`（`root` が無視され、`~/.claude/skills` にリンクされるため）

- [ ] **Step 4: `lib/targets.lua` に `root` を実装する**

`lib/targets.lua` の次の部分を:

```lua
-- Where each agent reads user-level skills, relative to $HOME.
M.AGENTS = {
```

次のように変える:

```lua
-- Where each agent reads skills, relative to $HOME (user level) or to the root option (a project).
M.AGENTS = {
```

`expand` を次のように変える（`what` はエラーメッセージに出す名前）:

```lua
local function expand(path, home, what)
    if path == "~" then
        return home
    elseif path:sub(1, 2) == "~/" then
        return file.join_path(home, path:sub(3))
    elseif path:sub(1, 1) == "/" then
        return path
    end
    error("mise-skill: " .. what .. " must be absolute or start with ~/: " .. path)
end
```

`resolve` のコメントと本体を次のように変える:

```lua
-- resolve(options, env_agents, home) -> the directories to link into, deduplicated, in order:
-- the agents (options.agents, else MISE_SKILL_AGENTS, else claude-code) under options.root, else
-- under home, then options.dirs.
function M.resolve(options, env_agents, home)
    local base = home
    if options.root ~= nil then
        base = expand(options.root, home, "root")
    end

    local agents = as_list(options.agents)
```

同じ関数の中の 2 か所も変える:

```lua
        add(file.join_path(base, rel))
```

（元は `add(file.join_path(home, rel))`）

```lua
        add(expand(dir, home, "dirs entries"))
```

（元は `add(expand(dir, home))`）

- [ ] **Step 5: テストが通ることを確認する**

Run: `sh tests/project.test.sh`
Expected: `ok project`

Run: `sh tests/link.test.sh`
Expected: `ok link`（`dirs` のエラーメッセージが変わっていないこと）

- [ ] **Step 6: コミットする**

```bash
git add lib/targets.lua tests/lib.sh tests/project.test.sh
git commit -F - <<'EOF'
feat: root オプションでエージェントのリンク先の基準を変えられるようにする

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 2: 流用時もリンクする（BackendExecEnv）

**Files:**
- Modify: `lib/links.lua:54-97`（`place` と `install`）
- Modify: `hooks/backend_install.lua:19`
- Modify: `hooks/backend_exec_env.lua`（全体）
- Modify: `tests/project.test.sh`

**Interfaces:**
- Consumes: `targets.resolve(options, env_agents, home)`（Task 1）、`skills.select(skills.discover(root), wanted)`（既存）
- Produces: `links.install(install_path, tmp, selected, dirs)`。第 2 引数は一時リンクを作る**パス**（従来はディレクトリ）。記録 `install_path/.mise-skill.json` は既存の一覧に追記される。

- [ ] **Step 1: 失敗するテストを足す**

`tests/project.test.sh` の `fx=...` の行の直後に次を足す:

```sh
# Lua's os.tmpname creates /tmp/lua_XXXXXX whatever TMPDIR says
luatmp() { find /tmp -maxdepth 1 -name 'lua_*' -user "$(id -u)" 2>/dev/null | sort; }
luatmp_before="$(luatmp)"
```

`# a relative root fails a fresh install` の行の直前に次を足す:

```sh
# the second project reuses the installed version and is linked too, from a subdirectory
wd="$h/work/b/sub" m install >/dev/null 2>&1 || fail "b: install"
[ -f "$h/work/b/.claude/skills/alpha/SKILL.md" ] || fail "b: claude-code link"
[ -f "$h/work/b/.agents/skills/alpha/SKILL.md" ] || fail "b: codex link"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "b: a should stay linked"

# entering a project (shell activation) is enough
wd="$h/work/c" m trust >/dev/null 2>&1 || fail "c: trust"
wd="$h/work/c" m hook-env -s zsh >/dev/null 2>&1 || fail "c: hook-env"
[ -f "$h/work/c/.claude/skills/alpha/SKILL.md" ] || fail "c: alpha should be linked"

# a bad root for an installed version is a plain warning, not an error with a stack trace
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" > "$h/work/c/mise.toml"
out="$(wd="$h/work/c" m env 2>&1)" || fail "bad: mise env should still work"
echo "$out" | grep -q 'mise-skill: could not link' || fail "bad: should warn, got: $out"
echo "$out" | grep -q 'stack traceback' && fail "bad: should not raise, got: $out"

# install -f in one project unlinks the others until they run mise again
wd="$h/work/b" m install -f "$fx@0.1.0" >/dev/null 2>&1 || fail "reinstall: install -f in b"
[ -f "$h/work/b/.claude/skills/alpha/SKILL.md" ] || fail "reinstall: b should be linked"
wd="$h/work/a" m env >/dev/null 2>&1 || fail "reinstall: env in a"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "reinstall: a should be linked again"

# removing the tool from every project and pruning removes the links of every project
for p in a b c; do echo '[tools]' > "$h/work/$p/mise.toml"; done
m prune >/dev/null 2>&1 || fail "prune"
for p in a b c; do
  [ -e "$h/work/$p/.claude/skills/alpha" ] && fail "prune: $p claude-code link should be gone"
  [ -e "$h/work/$p/.agents/skills/alpha" ] && fail "prune: $p codex link should be gone"
done

[ "$(luatmp)" = "$luatmp_before" ] || fail "tmp: os.tmpname files were left in /tmp"
```

- [ ] **Step 2: テストが失敗することを確認する**

Run: `sh tests/project.test.sh`
Expected: `FAIL: b: claude-code link`（流用時は BackendInstall が呼ばれず、リンクされないため）

- [ ] **Step 3: `lib/links.lua` の `place` を一時リンクのパスで受け取るようにする**

次の部分を:

```lua
-- place(src, dst, tmpdir): point dst at src. file.symlink fails when dst's parent is missing,
-- but file.move creates parents, so then the link is built in tmpdir and moved. If dst is on
-- another filesystem that move fails after creating the parent, and the link is built beside.
local function place(src, dst, tmpdir)
    if not file.exists(dirname(dst)) then
        local tmp = file.join_path(tmpdir, "mise-skill-link")
        os.remove(tmp)
```

次のように変える:

```lua
-- place(src, dst, tmp): point dst at src. file.symlink fails when dst's parent is missing,
-- but file.move creates parents, so then the link is built at tmp and moved. If dst is on
-- another filesystem that move fails after creating the parent, and the link is built beside.
local function place(src, dst, tmp)
    if not file.exists(dirname(dst)) then
        os.remove(tmp)
```

- [ ] **Step 4: `lib/links.lua` の `install` の記録を追記にする**

`-- install(install_path, tmpdir, selected, dirs): ...` から `M.install` の終わりまでを次に置き換える:

```lua
-- read_record(record) -> the links listed in record, or {} when it is missing or unreadable.
local function read_record(record)
    if not file.exists(record) then
        return {}
    end
    local ok, dsts = pcall(json.decode, file.read(record))
    if not ok or type(dsts) ~= "table" then
        return {}
    end
    return dsts
end

-- install(install_path, tmp, selected, dirs): mark each selected skill as owned by
-- install_path, link it into every dir, and add the links that were placed to the record.
-- One version serves every project that uses it, so earlier projects' links stay recorded.
function M.install(install_path, tmp, selected, dirs)
    local record = file.join_path(install_path, M.RECORD)
    local placed, seen = read_record(record), {}
    for _, dst in ipairs(placed) do
        seen[dst] = true
    end
    for _, skill in ipairs(selected) do
        write(file.join_path(skill.dir, M.MARKER), install_path)
        for _, dir in ipairs(dirs) do
            local dst = file.join_path(dir, skill.name)
            local kind, owner = M.classify(dst)
            if kind == "foreign" then
                log.warn("mise-skill: skipped " .. dst .. ": it exists and mise-skill did not create it")
            elseif kind == "ours" and dirname(owner) ~= dirname(install_path) then
                -- Another version of this tool is replaced (that is an upgrade); another tool is not.
                log.warn("mise-skill: skipped " .. dst .. ": another tool links it, installed at " .. owner)
            else
                local ok, err = pcall(place, skill.dir, dst, tmp)
                if ok and not seen[dst] then
                    seen[dst] = true
                    table.insert(placed, dst)
                elseif not ok then
                    log.warn("mise-skill: could not link " .. dst .. ": " .. tostring(err))
                end
            end
        end
    end
    write(record, json.encode(placed))
end
```

- [ ] **Step 5: `hooks/backend_install.lua` で一時リンクのパスを渡す**

```lua
    links.install(ctx.install_path, ctx.download_path, selected, dirs)
```

を次に変える:

```lua
    links.install(ctx.install_path, file.join_path(ctx.download_path, "mise-skill-link"), selected, dirs)
```

- [ ] **Step 6: `hooks/backend_exec_env.lua` でリンクする**

ファイル全体を次に置き換える:

```lua
local links = require("links")
local log = require("log")
local skills = require("skills")
local targets = require("targets")

-- BackendInstall runs once per version, but this runs for each config that uses the version
-- (mise caches the result per install and options), so a project with root = "{{config_root}}"
-- is linked even when the version was installed for another project. Failures only warn: mise
-- would print an error raised here with a stack trace and, since it caches only results, raise
-- it again on every run.
-- Skills add nothing to the environment.
function PLUGIN:BackendExecEnv(ctx)
    local tmp = os.tmpname()
    local ok, err = pcall(function()
        local dirs = targets.resolve(ctx.options, os.getenv("MISE_SKILL_AGENTS"), os.getenv("HOME"))
        local selected = skills.select(skills.discover(ctx.install_path), ctx.options.skills)
        links.install(ctx.install_path, tmp, selected, dirs)
    end)
    os.remove(tmp) -- os.tmpname creates the file, and the link is built there only sometimes
    if not ok then
        log.warn("mise-skill: could not link " .. ctx.tool .. ": " .. tostring(err))
    end
    return { env_vars = {} }
end
```

- [ ] **Step 7: テストが通ることを確認する**

Run: `sh tests/project.test.sh`
Expected: `ok project`

- [ ] **Step 8: 各テストが実装を検出できることを確認する（変更は戻す）**

1. `hooks/backend_exec_env.lua` の `os.remove(tmp)` の行を消して `sh tests/project.test.sh` → `FAIL: tmp: os.tmpname files were left in /tmp`。行を戻す。その後 `find /tmp -maxdepth 1 -name 'lua_*' -user "$(id -u)" -size 0 -newermt '<テスト開始時刻>' -delete` で、テストが残したファイルを消す。
2. `pcall(function() ... end)` を `true, nil; (function() ... end)()` に変えて `sh tests/project.test.sh` → `FAIL: bad: should not raise`。元に戻す。

- [ ] **Step 9: 全体を確認する**

Run: `mise run ci`
Expected: lint がすべて ✔、`ok install` / `ok link` / `ok project` / `ok versions`

- [ ] **Step 10: コミットする**

```bash
git add lib/links.lua hooks/backend_install.lua hooks/backend_exec_env.lua tests/project.test.sh
git commit -F - <<'EOF'
feat: 別のプロジェクトで入れた版を流用するときもリンクする

BackendInstall は版ごとに 1 回しか呼ばれないため、設定ごとに呼ばれる BackendExecEnv でも
リンクを張る。1 つの版を複数のプロジェクトが共有するので、リンクの記録は追記にする。

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 3: README

**Files:**
- Modify: `README.md`
- Modify: `README.ja.md`

**Interfaces:**
- Consumes: Task 1・2 の挙動
- Produces: なし

- [ ] **Step 1: `README.md` のオプション表に `root` を足す**

```markdown
| `dirs` | none | Extra directories (absolute or `~/...`) to link into |
```

の直後に次の行を足す:

```markdown
| `root` | `~` | Base of the agents' directories (absolute or `~/...`), e.g. `"{{config_root}}"` |
```

- [ ] **Step 2: `README.md` に「Project scope」の節を足す**

`## Keeping links in sync` の直前に次を足す:

````markdown
## Project scope

In a project's `mise.toml`, set `root = "{{config_root}}"` to link into the project's own
`.claude/skills` / `.agents/skills`. mise expands `{{config_root}}` to the project directory, so
the file can be committed and shared.

```toml
# <project>/mise.toml
[tools]
"skill:example/writing-guide" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
```

A version is shared in mise's installs directory, and a project that uses a version installed for
another project is linked too (on `mise install`, or when an activated shell enters the project).

- The links point into this machine's installs directory: gitignore `.claude/skills/<skill name>`
  and `.agents/skills/<skill name>`.
- Removing the tool from a project's `mise.toml` leaves its links until the version is pruned.
- A link removed by hand comes back after `mise cache clear`.
- `mise install -f` in one project removes the other projects' links too; each gets them back the
  next time mise runs there.

````

- [ ] **Step 3: `README.ja.md` のオプション表に `root` を足す**

```markdown
| `dirs` | なし | 追加でリンクするディレクトリ（絶対パスか `~/...`） |
```

の直後に次の行を足す:

```markdown
| `root` | `~` | エージェントのディレクトリの基準（絶対パスか `~/...`）。例: `"{{config_root}}"` |
```

- [ ] **Step 4: `README.ja.md` に「プロジェクト単位」の節を足す**

`## リンクを最新に保つ` の直前に次を足す:

````markdown
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

````

- [ ] **Step 5: 確認する**

Run: `mise run lint`
Expected: すべて ✔

Run: `git diff --stat`
Expected: `README.md` と `README.ja.md` だけが変わっている

- [ ] **Step 6: コミットする**

```bash
git add README.md README.ja.md
git commit -F - <<'EOF'
docs: root オプションとプロジェクト単位の使い方を README に書く

Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>
EOF
```

---

### Task 4: 実環境での確認と PR #7 の更新

**Files:** なし（PR の更新のみ）

- [ ] **Step 1: 隔離した mise 環境で 2 つのプロジェクトから install / prune する**

`MISE_DATA_DIR` / `MISE_CACHE_DIR` / `MISE_STATE_DIR` / `MISE_CONFIG_DIR` / `MISE_GLOBAL_CONFIG_FILE` を scratchpad 下に向け、`MISE_TRUSTED_CONFIG_PATHS` で scratchpad を trust したうえで、次を順に実行する。

1. `mise plugins link skill <この checkout>`
2. `p1/mise.toml` と `p2/mise.toml` に、Task 1 の Step 2 と同じ `root = "{{config_root}}"`、`agents = ["claude-code", "codex"]` の設定を書く
3. p1 で `mise install`、p2 で `mise install` を実行する
4. 両方の `.claude/skills` と `.agents/skills` を `ls -l` で見る
5. 両方の `[tools]` を空にして `mise prune --yes` を実行し、`ls` で空になったことを確かめる

この出力を PR の Verification に貼る。

- [ ] **Step 2: PR #7 を更新する**

```bash
git push --force-with-lease origin HEAD
```

`gh pr edit 7 --title "feat: root オプションでプロジェクト内にスキルをリンクする" --body-file <file>` で本文を差し替える。本文は `.github/pull_request_template.md` の見出し（What and why / Verification / Scope / Release notes label / AI use (verified?)）に沿って書き、末尾を `🤖 Generated with [Claude Code](https://claude.com/claude-code)` で締める。Scope には、新しい spec `docs/superpowers/specs/2026-10-19-project-scope-design.md` に従ったこと、初期設計の spec は変更していないことを書く。Release notes label は `Kind: Feature`。
