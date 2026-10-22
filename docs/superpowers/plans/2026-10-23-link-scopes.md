# ユーザーとプロジェクトのスコープ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** スキルのリンクを「設定 × ツール」単位にし、グローバル設定は `~` に、`root = "{{config_root}}"` を書いたプロジェクトの設定はそのプロジェクトにリンクする。

**Architecture:** リンクを張る処理を BackendInstall と BackendExecEnv の両方から呼ぶ。基準ディレクトリは、hook の中から呼ぶ `mise ls --current --json` で「ctx の版が cwd で有効か」「グローバル由来か」を確かめて決める。記録 `.mise-skill.json` は「基準 → リンクの一覧」の表にし、基準ごとに前回分と突き合わせて要らなくなったリンクを外す。

**Tech Stack:** mise の vfox 形式 backend plugin（Lua。mise 内蔵の `file` / `json` / `log` モジュールと Lua 標準の `io.popen` / `os.*`）、テストは素の sh。

**Spec:** `docs/superpowers/specs/2026-10-23-link-scopes-design.md`（前提: `docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md`）

## Global Constraints

- 追加のツールを要求しない。`metadata.lua` の `depends` / `systemDependencies` は使わない。
- エラー・警告の文言は `mise-skill: ` で始める。
- `root` の無いプロジェクトの設定のエラー文言: `mise-skill: <tool> is declared in <source.path> without root; add root = "{{config_root}}"`
- 相対パスの `root` のエラー文言: `mise-skill: root must be absolute or start with ~/: <値>`
- ExecEnv の警告文言: `mise-skill: could not link <tool>: <理由>`
- ExecEnv がエラーにするのは「`root` の無いプロジェクトの設定」だけ。ほかは警告にとどめ、`{ env_vars = {} }` を返す。
- `metadata.lua` の版は上げない（別の PR で上げる）。
- 初期設計の spec と plan は、冒頭の注記 1 行のほかは変更しない。
- 検証は `mise run ci`（lint + test）。テストは実際に GitHub の fixture を取得するので、gh CLI のログインか `GITHUB_TOKEN` が要る。
- コメントは英語で、周りのコードと同じ密度にする。Lua は stylua（`stylua.toml`）で整形する。

## File Structure

| ファイル | 役割 | 変更 |
|---|---|---|
| `lib/targets.lua` | 基準ディレクトリとリンク先ディレクトリの決定 | `base()` を追加、`resolve()` に `base` 引数、`expand()` の文言を引数化 |
| `lib/links.lua` | リンクの作成・突き合わせ・記録・解除 | `install()` を `sync()` に置き換え、記録を表に、一時リンクを `install_path` に |
| `hooks/backend_install.lua` | 取得・展開とリンク | `targets.base()` と `links.sync()` を使う |
| `hooks/backend_exec_env.lua` | 設定ごとのリンク | リンク処理を行う |
| `hooks/backend_uninstall.lua` | 解除 | 変更なし（`links.uninstall` の中身が変わる） |
| `tests/lib.sh` | テストの共通処理 | `m()` の実行ディレクトリを `wd` で変えられるように |
| `tests/link.test.sh` | グローバルのリンク | `install -f` の項目を `mise env` に、引数だけの install と古い記録の項目を追加 |
| `tests/project.test.sh` | プロジェクトのリンク | 新規 |
| `README.md` / `README.ja.md` | 利用者向けの説明 | `root`・スコープ・制約 |
| `docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md` | 初期設計 | 冒頭に注記 1 行 |

---

### Task 1: グローバルのリンクを ExecEnv でも張る

`root` はまだ扱わない（Task 2）。この Task の後、グローバル設定のオプション変更が `mise env` だけで反映され、`root` の無いプロジェクトの設定はエラーになる。

**Files:**
- Modify: `lib/targets.lua`
- Modify: `lib/links.lua`
- Modify: `hooks/backend_install.lua`
- Modify: `hooks/backend_exec_env.lua`
- Modify: `tests/lib.sh`
- Modify: `tests/link.test.sh`
- Create: `tests/project.test.sh`

**Interfaces:**
- Produces:
  - `targets.NO_ROOT` (string): `root` の無いプロジェクトの設定のエラー文言に含まれる目印 `"without root; add root"`。
  - `targets.base(install_path: string, options: table, home: string) -> string|nil`: 基準ディレクトリ。cwd で有効な版でなければ `nil`。`root` の無いプロジェクトの設定ならエラー。
  - `targets.resolve(options: table, env_agents: string|nil, home: string, base: string|nil) -> string[]`: エージェントのディレクトリ（`base`、`nil` なら `home` の下）と `dirs`。
  - `links.sync(install_path: string, base: string, selected: {name, dir}[], dirs: string[])`: リンクを張り、`base` の前回分と突き合わせ、記録する。
  - `links.uninstall(install_path: string)`: 記録の全基準のリンクを外す（シグネチャは今と同じ）。
  - `tests/lib.sh` の `m()`: `wd` があればそこで、無ければ `$h/work` で mise を実行する。

- [ ] **Step 1: `tests/lib.sh` の `m()` を `wd` に対応させる**

`tests/lib.sh` の `m()` とそのコメントを次に置き換える。

```sh
# m <args...>: run mise inside $h (in $wd if set, else $h/work) with no XDG / MISE_* overrides
# leaking in from the caller. Set wd only in a subshell or command substitution, e.g.
# (wd=... m install): a prefix assignment on a function can persist in some shells (bash POSIX mode).
m() {
  (cd "${wd:-$h/work}" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    -u MISE_DATA_DIR -u MISE_CONFIG_DIR -u MISE_CACHE_DIR -u MISE_STATE_DIR -u MISE_ENV \
    -u MISE_SKILL_AGENTS MISE_CEILING_PATHS="$h" HOME="$h" GH_CONFIG_DIR="$gh_config" MISE_YES=1 mise "$@")
}
```

- [ ] **Step 2: `tests/link.test.sh` に失敗するテストを書く**

(a) `# install -f applies changed options and drops links that are no longer wanted` から、`m prune` の直前の `[ -L "$h/.agents/skills/alpha" ] || fail "reinstall: codex link should stay"` までのブロックを、次に置き換える。

```sh
# changed options apply on the next mise run, without install -f, and drop links no longer wanted
cat <<'EOT' | config
[tools]
"skill:bright-room-sandbox/mise-skill-fixtures" = { version = "0.2.0", agents = ["claude-code", "codex"] }
EOT
m env >/dev/null 2>&1 || fail "options: env after adding codex"
[ -L "$h/.agents/skills/alpha" ] || fail "options: codex link should appear"
cat <<'EOT' | config
[tools]
"skill:bright-room-sandbox/mise-skill-fixtures" = { version = "0.2.0", agents = ["codex"], skills = ["alpha", "beta"] }
EOT
m env >/dev/null 2>&1 || fail "options: env after dropping claude-code and gamma"
[ -e "$h/.claude/skills/alpha" ] && fail "options: claude-code link should be gone"
[ -e "$h/.agents/skills/gamma" ] && fail "options: gamma link should be gone"
[ -L "$h/.agents/skills/alpha" ] || fail "options: codex link should stay"
```

(b) 直後の prune のブロックはそのまま残す（`alpha` は codex に残っているので、prune で消えることを確かめられる）。

(c) `echo "ok link"` の直前に次を足す。

```sh
# a version installed only by arguments, which no config requests, is not linked
new_home args
echo '[tools]' | config
m install "$fx@0.1.0" >/dev/null 2>&1 || fail "args: install"
[ -e "$h/.claude/skills/alpha" ] && fail "args: no config requests it, so nothing should be linked"

# a record in the list form of mise-skill 0.1 still has its links removed by prune
new_home legacy
printf '[tools]\n"%s" = "0.1.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "legacy: install"
printf '["%s"]' "$h/.claude/skills/alpha" > "$(installs)/$dir/0.1.0/.mise-skill.json"
echo '[tools]' | config
m prune >/dev/null 2>&1 || fail "legacy: prune"
[ -e "$h/.claude/skills/alpha" ] && fail "legacy: the listed link should be gone"
```

- [ ] **Step 3: `tests/project.test.sh` を作る（`root` の無いプロジェクトの設定）**

```sh
#!/bin/sh
# Project scope: a project config links into the project with root = "{{config_root}}", and is an
# error without it.
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }
fx=skill:bright-room-sandbox/mise-skill-fixtures
dir=skill-bright-room-sandbox-mise-skill-fixtures

# a project config without root is an error, and does not keep the global config from linking
new_home no-root
echo '[tools]' | config
mkdir -p "$h/work/d"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" > "$h/work/d/mise.toml"
if err="$(wd="$h/work/d" m install 2>&1)"; then fail "no-root: install in d should fail"; fi
echo "$err" | grep -q 'without root; add root' || fail "no-root: install error should ask for root, got: $err"
m install "$fx@0.2.0" >/dev/null 2>&1 || fail "no-root: install by arguments"
m cache clear >/dev/null 2>&1 || fail "no-root: cache clear"
out="$(wd="$h/work/d" m env 2>&1)" || true
echo "$out" | grep -q 'without root; add root' || fail "no-root: mise env in d should ask for root, got: $out"
[ -e "$h/work/d/.claude/skills/alpha" ] && fail "no-root: d must not be linked"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" | config
m env >/dev/null 2>&1 || fail "no-root: global env"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.2.0" ] ||
  fail "no-root: the global config should still link 0.2.0"

echo "ok project"
```

`m cache clear` は、引数だけの install の後に mise が呼ぶ ExecEnv（cwd で有効でない版なので何もしない）の結果を捨てるため。spec の「手順 1 の何もしない結果もキャッシュされる」を参照。

- [ ] **Step 4: テストが失敗することを確かめる**

Run: `sh tests/link.test.sh; sh tests/project.test.sh`
Expected: `link.test.sh` は `FAIL: options: codex link should appear`、`project.test.sh` は `FAIL: no-root: install in d should fail`（今は `root` の無いプロジェクトの設定でも `~` にリンクして成功する）。

- [ ] **Step 5: `lib/targets.lua` を書き換える**

ファイル全体を次にする。

```lua
local file = require("file")
local json = require("json")

local M = {}

-- Where each agent reads skills, relative to a base: $HOME for the global config.
M.AGENTS = {
    ["claude-code"] = ".claude/skills",
    ["codex"] = ".agents/skills",
}

-- In the error for a project config without root; BackendExecEnv raises only that error.
M.NO_ROOT = "without root; add root"

local function as_list(value)
    if value == nil then
        return nil
    elseif type(value) == "string" then
        return { value }
    end
    return value
end

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

-- requested(flags, install_path) -> the tool name and entry in `mise ls --json <flags>`, run
-- where mise was started, whose install_path is install_path; nil when none is or mise fails.
-- Nothing in ctx tells which config a hook was called for, but `mise ls` does.
local function requested(flags, install_path)
    local p = io.popen("mise ls --json " .. flags .. " 2>/dev/null")
    if p == nil then
        return nil
    end
    local out = p:read("*a")
    p:close()
    local ok, tools = pcall(json.decode, out)
    if not ok or type(tools) ~= "table" then
        return nil
    end
    for name, entries in pairs(tools) do
        for _, entry in ipairs(entries) do
            if entry.install_path == install_path then
                return name, entry
            end
        end
    end
    return nil
end

-- base(install_path, options, home) -> the directory the agents' skill directories are under, or
-- nil when the config in effect here does not use install_path: after an install mise calls the
-- hooks for every installed version, and `mise use` installs before it writes the config.
-- A project config without root raises: ExecEnv results are cached per install and options, so a
-- quiet nil here would stop a global config with the same options from ever being linked.
function M.base(install_path, options, home)
    local name, entry = requested("--current", install_path)
    if name == nil then
        return nil
    end
    if requested("--current --global", install_path) ~= nil then
        return home
    end
    local source = entry.source and entry.source.path or "a project config"
    error("mise-skill: " .. name .. " is declared in " .. tostring(source) .. " " .. M.NO_ROOT .. ' = "{{config_root}}"')
end

-- resolve(options, env_agents, home, base) -> the directories to link into, deduplicated, in order:
-- the agents (options.agents, else MISE_SKILL_AGENTS, else claude-code) under base (home when nil),
-- then options.dirs.
function M.resolve(options, env_agents, home, base)
    base = base or home
    local agents = as_list(options.agents)
    if agents == nil and env_agents ~= nil and env_agents ~= "" then
        agents = {}
        for name in env_agents:gmatch("[^,%s]+") do
            table.insert(agents, name)
        end
    end
    agents = agents or { "claude-code" }

    local dirs, seen = {}, {}
    local function add(dir)
        if not seen[dir] then
            seen[dir] = true
            table.insert(dirs, dir)
        end
    end
    for _, name in ipairs(agents) do
        local rel = M.AGENTS[name]
        if rel == nil then
            error("mise-skill: unknown agent " .. name .. " (known: claude-code, codex)")
        end
        add(file.join_path(base, rel))
    end
    for _, dir in ipairs(as_list(options.dirs) or {}) do
        add(expand(dir, home, "dirs entries"))
    end
    return dirs
end

return M
```

- [ ] **Step 6: `lib/links.lua` を書き換える**

`M.RECORD` の行の後に `M.LEGACY` を足し、`place` から下（`place`、`M.install`、`M.uninstall`）を次に置き換える。`write`、`M.classify`、`dirname`、`link_beside` は変えない。

```lua
M.RECORD = ".mise-skill.json" -- in install_path; the links this version placed, by base directory
M.LEGACY = "" -- the record's key for links recorded as a plain list, by mise-skill 0.1
```

```lua
-- place(src, dst, tmp): point dst at src. file.symlink fails when dst's parent is missing,
-- but file.move creates parents, so then the link is built at tmp and moved. If dst is on
-- another filesystem that move fails after creating the parent, and the link is built beside.
local function place(src, dst, tmp)
    if not file.exists(dirname(dst)) then
        os.remove(tmp)
        file.symlink(src, tmp)
        local ok, err = pcall(file.move, tmp, dst)
        os.remove(tmp)
        if ok then
            return
        elseif not file.exists(dirname(dst)) then
            error(err, 0)
        end
    end
    link_beside(src, dst)
end

-- remove(dst, install_path): remove dst if it is a mise-skill link that still points at
-- install_path. After an upgrade an old version's links already point elsewhere.
local function remove(dst, install_path)
    local kind, owner = M.classify(dst)
    if kind == "ours" and owner == install_path then
        local ok, err = os.remove(dst)
        if not ok then
            log.warn("mise-skill: could not remove " .. dst .. ": " .. tostring(err))
        end
    end
end

-- read_record(install_path) -> { [base] = { dst, ... } }, or {} when it is missing or unreadable.
-- A plain list is the record of mise-skill 0.1; it is kept under M.LEGACY so uninstall removes it.
local function read_record(install_path)
    local record = file.join_path(install_path, M.RECORD)
    if not file.exists(record) then
        return {}
    end
    local ok, value = pcall(json.decode, file.read(record))
    if not ok or type(value) ~= "table" then
        return {}
    end
    if value[1] ~= nil then
        return { [M.LEGACY] = value }
    end
    return value
end

-- write_record(install_path, by_base): rename over the record so a concurrent read_record never
-- sees a partial file.
local function write_record(install_path, by_base)
    local record = file.join_path(install_path, M.RECORD)
    local tmp = record .. ".tmp" .. tostring(os.time()) .. tostring(math.random(1e9))
    write(tmp, json.encode(by_base))
    local ok, err = os.rename(tmp, record)
    if not ok then
        os.remove(tmp)
        error(err, 0)
    end
end

-- sync(install_path, base, selected, dirs): for the config whose base directory is base, mark
-- each selected skill as owned by install_path, link it into every dir, remove what this config
-- linked last time and no longer wants, and record the links under base. One version serves
-- every config that uses it, so the other bases are other configs and are left alone.
function M.sync(install_path, base, selected, dirs)
    local tmp = file.join_path(install_path, ".mise-skill-link")
    local by_base = read_record(install_path)
    local placed, wanted = {}, {}
    for _, skill in ipairs(selected) do
        write(file.join_path(skill.dir, M.MARKER), install_path)
        for _, dir in ipairs(dirs) do
            local dst = file.join_path(dir, skill.name)
            wanted[dst] = true
            local kind, owner = M.classify(dst)
            if kind == "foreign" then
                log.warn("mise-skill: skipped " .. dst .. ": it exists and mise-skill did not create it")
            elseif kind == "ours" and dirname(owner) ~= dirname(install_path) then
                -- Another version of this tool is replaced (that is an upgrade); another tool is not.
                log.warn("mise-skill: skipped " .. dst .. ": another tool links it, installed at " .. owner)
            else
                local ok, err = pcall(place, skill.dir, dst, tmp)
                if ok then
                    table.insert(placed, dst)
                else
                    log.warn("mise-skill: could not link " .. dst .. ": " .. tostring(err))
                end
            end
        end
    end
    for _, dst in ipairs(by_base[base] or {}) do
        if not wanted[dst] then
            remove(dst, install_path)
        end
    end
    by_base[base] = placed
    write_record(install_path, by_base)
end

-- uninstall(install_path): remove the links this version recorded, for every base, that still
-- point at it. ctx.options is unreliable here (defaults only during prune), so use the record.
function M.uninstall(install_path)
    for _, dsts in pairs(read_record(install_path)) do
        for _, dst in ipairs(dsts) do
            remove(dst, install_path)
        end
    end
end
```

- [ ] **Step 7: `hooks/backend_install.lua` を書き換える**

ファイル全体を次にする。

```lua
local archiver = require("archiver")
local file = require("file")
local http = require("http")
local github = require("github")
local links = require("links")
local skills = require("skills")
local targets = require("targets")

function PLUGIN:BackendInstall(ctx)
    -- Check the options before downloading anything.
    local home = os.getenv("HOME")
    local base = targets.base(ctx.install_path, ctx.options, home)
    local dirs = targets.resolve(ctx.options, os.getenv("MISE_SKILL_AGENTS"), home, base)

    local ref = github.ref_for(ctx.tool, ctx.version)
    local archive = file.join_path(ctx.download_path, "source.tar.gz")
    http.download_file({ url = github.tarball_url(ctx.tool, ref) }, archive)
    archiver.decompress(archive, ctx.install_path, { strip_components = 1 })

    local selected = skills.select(skills.discover(ctx.install_path), ctx.options.skills)
    -- With no base the config is not written yet (mise use) or does not use this version;
    -- BackendExecEnv links it where a config does.
    if base ~= nil then
        links.sync(ctx.install_path, base, selected, dirs)
    end
    return {}
end
```

- [ ] **Step 8: `hooks/backend_exec_env.lua` を書き換える**

ファイル全体を次にする。

```lua
local links = require("links")
local log = require("log")
local skills = require("skills")
local targets = require("targets")

-- link(ctx): link this version for the config in effect here. BackendInstall runs once per
-- version, but mise calls this for each set of options that uses it (it caches the result per
-- install and options), so a config is linked even when the version was installed for another.
local function link(ctx)
    local home = os.getenv("HOME")
    local base = targets.base(ctx.install_path, ctx.options, home)
    if base == nil then
        return
    end
    local dirs = targets.resolve(ctx.options, os.getenv("MISE_SKILL_AGENTS"), home, base)
    local selected = skills.select(skills.discover(ctx.install_path), ctx.options.skills)
    links.sync(ctx.install_path, base, selected, dirs)
end

-- Skills add nothing to the environment. A project config without root raises, so that mise does
-- not cache the result; anything else only warns, since mise prints an error raised here with a
-- stack trace on every run.
function PLUGIN:BackendExecEnv(ctx)
    local ok, err = pcall(link, ctx)
    if not ok then
        if tostring(err):find(targets.NO_ROOT, 1, true) then
            error(err, 0)
        end
        log.warn("mise-skill: could not link " .. ctx.tool .. ": " .. tostring(err))
    end
    return { env_vars = {} }
end
```

- [ ] **Step 9: テストが通ることを確かめる**

Run: `mise run format && mise run ci`
Expected: lint はすべて ✔、テストは `ok install` / `ok link` / `ok project` / `ok versions`。

`ok install` も確かめる。`tests/install.test.sh` は空の `[tools]` で引数だけの install を行うので、`targets.base` が `nil` を返してもスキルの選択（`skills` に無い名前など）の検査は従来どおり動く必要がある。

- [ ] **Step 10: Commit**

```bash
git add lib/targets.lua lib/links.lua hooks/backend_install.lua hooks/backend_exec_env.lua tests/lib.sh tests/link.test.sh tests/project.test.sh
git commit -m "feat: 設定ごとにリンクし、オプションの変更を install -f なしで反映する"
```

---

### Task 2: `root` でプロジェクトにリンクする

**Files:**
- Modify: `lib/targets.lua`
- Modify: `tests/project.test.sh`

**Interfaces:**
- Consumes: Task 1 の `targets.base` / `targets.resolve` / `links.sync`、`tests/lib.sh` の `wd`。
- Produces: `targets.base` が `options.root` を扱う（cwd で有効な版のときだけ）。

- [ ] **Step 1: `tests/project.test.sh` に失敗するテストを書く**

`echo "ok project"` の直前に次を足す。

```sh
new_home project
echo '[tools]' | config
for p in a b c; do
  mkdir -p "$h/work/$p/sub"
  printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}", agents = ["claude-code", "codex"] }\n' \
    "$fx" > "$h/work/$p/mise.toml"
done

# the first project installs the version and is linked for both agents
(wd="$h/work/a" m install) >/dev/null 2>&1 || fail "a: install"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "a: claude-code link"
[ -f "$h/work/a/.agents/skills/alpha/SKILL.md" ] || fail "a: codex link"
[ -e "$h/.claude/skills/alpha" ] && fail "a: root should replace ~ for the agents"

# the second project reuses the installed version and is linked too, from a subdirectory
(wd="$h/work/b/sub" m install) >/dev/null 2>&1 || fail "b: install"
[ -f "$h/work/b/.claude/skills/alpha/SKILL.md" ] || fail "b: claude-code link"
[ -f "$h/work/b/.agents/skills/alpha/SKILL.md" ] || fail "b: codex link"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "b: a should stay linked"

# entering a project (shell activation) is enough
(wd="$h/work/c" m trust) >/dev/null 2>&1 || fail "c: trust"
(wd="$h/work/c" m hook-env -s zsh) >/dev/null 2>&1 || fail "c: hook-env"
[ -f "$h/work/c/.claude/skills/alpha/SKILL.md" ] || fail "c: alpha should be linked"

# changing skills in one project changes only that project's links
printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}", agents = ["claude-code", "codex"], skills = ["alpha"] }\n' \
  "$fx" > "$h/work/a/mise.toml"
(wd="$h/work/a" m env) >/dev/null 2>&1 || fail "skills: env in a"
[ -e "$h/work/a/.claude/skills/beta" ] && fail "skills: beta should be gone from a"
[ -L "$h/work/a/.claude/skills/alpha" ] || fail "skills: alpha should stay in a"
[ -L "$h/work/b/.claude/skills/beta" ] || fail "skills: b should keep beta"

# a bad root for an installed version is a plain warning, not an error with a stack trace
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" > "$h/work/c/mise.toml"
out="$(wd="$h/work/c" m env 2>&1)" || fail "bad: mise env should still work"
echo "$out" | grep -q 'mise-skill: could not link' || fail "bad: should warn, got: $out"
echo "$out" | grep -q 'stack traceback' && fail "bad: should not raise, got: $out"

# install -f in one project unlinks the others until they run mise again
(wd="$h/work/b" m install -f "$fx@0.1.0") >/dev/null 2>&1 || fail "reinstall: install -f in b"
[ -f "$h/work/b/.claude/skills/alpha/SKILL.md" ] || fail "reinstall: b should be linked"
(wd="$h/work/a" m env) >/dev/null 2>&1 || fail "reinstall: env in a"
[ -f "$h/work/a/.claude/skills/alpha/SKILL.md" ] || fail "reinstall: a should be linked again"

# removing the tool from every project and pruning removes the links of every project
for p in a b c; do echo '[tools]' > "$h/work/$p/mise.toml"; done
m prune >/dev/null 2>&1 || fail "prune"
for p in a b c; do
  [ -e "$h/work/$p/.claude/skills/alpha" ] && fail "prune: $p claude-code link should be gone"
  [ -e "$h/work/$p/.agents/skills/alpha" ] && fail "prune: $p codex link should be gone"
done

# a relative root fails a fresh install
new_home bad-root
printf '[tools]\n"%s" = { version = "0.1.0", root = "relative" }\n' "$fx" | config
if err="$(m install 2>&1)"; then fail "bad-root: install should fail"; fi
echo "$err" | grep -q 'root must be absolute or start with ~/: relative' ||
  fail "bad-root: error should name root, got: $err"

# a project on an older version than the global config: each keeps its own version, although
# installing in the project makes mise call ExecEnv for both versions with the project's options
new_home pinned
mkdir -p "$h/work/p"
printf '[tools]\n"%s" = "0.2.0"\n' "$fx" | config
m install >/dev/null 2>&1 || fail "pinned: global install"
printf '[tools]\n"%s" = { version = "0.1.0", root = "{{config_root}}" }\n' "$fx" > "$h/work/p/mise.toml"
(wd="$h/work/p" m install) >/dev/null 2>&1 || fail "pinned: install in p"
[ "$(cat "$h/work/p/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.1.0" ] ||
  fail "pinned: p should link 0.1.0"
[ "$(cat "$h/.claude/skills/alpha/.mise-skill")" = "$(installs)/$dir/0.2.0" ] ||
  fail "pinned: ~ should stay on 0.2.0"
```

- [ ] **Step 2: テストが失敗することを確かめる**

Run: `sh tests/project.test.sh`
Expected: `FAIL: a: install`（`root` を書いても、まだプロジェクトの設定として `without root` のエラーになる）。

- [ ] **Step 3: `targets.base` に `root` を足す**

`lib/targets.lua` の `M.AGENTS` のコメントと `M.base` を次に置き換える。

```lua
-- Where each agent reads skills, relative to a base: $HOME for the global config, the root option
-- for a project.
```

```lua
-- base(install_path, options, home) -> the directory the agents' skill directories are under, or
-- nil when the config in effect here does not use install_path: after an install mise calls the
-- hooks for every installed version, with the options of the version in effect, and `mise use`
-- installs before it writes the config. options.root wins; without it the config must be global.
-- A project config without root raises: ExecEnv results are cached per install and options, so a
-- quiet nil here would stop a global config with the same options from ever being linked.
function M.base(install_path, options, home)
    local name, entry = requested("--current", install_path)
    if name == nil then
        return nil
    end
    if options.root ~= nil then
        return expand(options.root, home, "root")
    end
    if requested("--current --global", install_path) ~= nil then
        return home
    end
    local source = entry.source and entry.source.path or "a project config"
    error("mise-skill: " .. name .. " is declared in " .. tostring(source) .. " " .. M.NO_ROOT .. ' = "{{config_root}}"')
end
```

- [ ] **Step 4: テストが通ることを確かめる**

Run: `mise run format && mise run ci`
Expected: lint はすべて ✔、テストは `ok install` / `ok link` / `ok project` / `ok versions`。

- [ ] **Step 5: Commit**

```bash
git add lib/targets.lua tests/project.test.sh
git commit -m "feat: root オプションでプロジェクト内にスキルをリンクする"
```

---

### Task 3: README と初期設計の注記

**Files:**
- Modify: `README.md`
- Modify: `README.ja.md`
- Modify: `docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md`

**Interfaces:**
- Consumes: Task 1・2 の挙動（spec の「使い方」「制約」）。

- [ ] **Step 1: `README.md` を直す**

(a) 冒頭の toml の例の後、`mise install` の段落の後に、プロジェクトの例を足す。

````markdown
A project can have its own skills: put them in the project's `mise.toml` with
`root = "{{config_root}}"`, and they are linked into the project's `.claude/skills` /
`.agents/skills` instead of your home.

```toml
# <project>/mise.toml
[tools]
"skill:example/prose-lint" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
```
````

(b) Options の表に行を足す。

```markdown
| `root` | none | Base of the agents' directories (absolute or `~/...`); `{{config_root}}` in a project |
```

Agent の表の見出しの後に 1 文を足す: `The directories are under your home, or under `root` when it is set.`

(c) 「Keeping links in sync」の表を次にする。

```markdown
| To | Run |
|---|---|
| add a skill or move to a new version | `mise install` / `mise upgrade` |
| apply changed `skills` / `agents` / `dirs` / `root` | nothing: the next mise run applies them |
| switch to a version that is already installed | `mise cache clear` |
| move a `ref:` install (e.g. `ref:main`) to the branch's latest commit | `mise install -f skill:owner/repo@ref:main` |
| remove a skill's links | delete it from `[tools]`, then `mise prune` |
```

(d) 「Keeping links in sync」の最後に「Scopes」の節を足す。

```markdown
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
```

- [ ] **Step 2: `README.ja.md` を同じ内容で直す**

(a) `mise install` の段落の後:

````markdown
プロジェクトだけで使うスキルは、そのプロジェクトの `mise.toml` に `root = "{{config_root}}"` を
付けて書く。リンク先がホームではなく、プロジェクトの `.claude/skills` / `.agents/skills` になる。

```toml
# <project>/mise.toml
[tools]
"skill:example/prose-lint" = { version = "latest", root = "{{config_root}}", agents = ["claude-code", "codex"] }
```
````

(b) オプションの表に行を足す。

```markdown
| `root` | なし | エージェントのディレクトリの基準（絶対パスか `~/...`）。プロジェクトでは `{{config_root}}` |
```

エージェントの表の後に 1 文を足す: `ディレクトリはホームの下、`root` があれば `root` の下にある。`

(c) 「リンクを最新に保つ」の表を次にする。

```markdown
| やりたいこと | 実行するもの |
|---|---|
| スキルを足す、新しい版に上げる | `mise install` / `mise upgrade` |
| `skills` / `agents` / `dirs` / `root` の変更を反映する | 何もしない（次に mise が動いたときに反映される） |
| 入れ済みの版に切り替える | `mise cache clear` |
| `ref:` で入れたもの（例: `ref:main`）をブランチの最新コミットに上げる | `mise install -f skill:owner/repo@ref:main` |
| スキルのリンクを外す | `[tools]` から消して `mise prune` |
```

(d) 「リンクを最新に保つ」の最後に「スコープ」の節を足す。

```markdown
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
```

- [ ] **Step 3: 初期設計の文書に注記を足す**

`docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md` の `- 作業ディレクトリ: ...` の行の後に次の 1 行を足す。

```markdown
- リンクの張り方・外し方は `2026-10-23-link-scopes-design.md` で置き換えた。
```

- [ ] **Step 4: 確かめる**

Run: `mise run ci`
Expected: lint はすべて ✔、テストは 4 つとも ok。README の表が崩れていないことを目で確かめる（`grep -n 'root' README.md README.ja.md`）。

- [ ] **Step 5: Commit**

```bash
git add README.md README.ja.md docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md
git commit -m "docs: プロジェクトのスコープと root を README に書く"
```

---

## 完了後

- macOS では CI（`test (macos-latest)`）で確かめる。
- PR を出すときに PR #7 を閉じる（閉じる前にユーザーに確認する）。
