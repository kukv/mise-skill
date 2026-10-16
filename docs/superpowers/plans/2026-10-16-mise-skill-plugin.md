# mise-skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** GitHub 上のエージェントスキルを mise の `[tools]` で宣言し、`mise install` だけで `~/.claude/skills` / `~/.agents/skills` に symlink で配る backend plugin `kukv/mise-skill` を作る。

**Architecture:** mise の backend plugin（Lua 5.1 の hooks）。BackendInstall が GitHub の tarball を `install_path` に展開し、続けてスキルへの symlink を張る。BackendUninstall が自分の張ったリンクだけを外す。ロジックは `lib/` の 4 モジュール（github / skills / targets / links）に分け、hooks は薄く保つ。

**Tech Stack:** Lua 5.1（mise 内蔵ランタイム、内蔵モジュール `http` `json` `file` `archiver` `semver` `log` のみ）、テストは POSIX sh + 実物の mise、CI は GitHub Actions。

**Spec:** `docs/superpowers/specs/2026-10-16-mise-skill-plugin-design.md`

## Global Constraints

- 外部ツールに依存しない。hooks は mise 内蔵の Lua モジュールと Lua 標準ライブラリだけを使う。`cmd.exec` / `os.execute` / `io.popen` は使わない。`metadata.lua` に `depends` / `systemDependencies` を書かない。
- 対象はグローバル（`$HOME` 配下）のみ、GitHub のみ、Linux / macOS のみ。
- エージェント対応表: `claude-code` → `~/.claude/skills`、`codex` → `~/.agents/skills`。
- 全体の既定エージェントは環境変数 `MISE_SKILL_AGENTS`（カンマ区切り）。未設定なら `claude-code`。
- ツールオプション: `skills`（配列）、`agents`（配列）、`dirs`（配列、`~` または絶対パス）。
- タグは先頭の `v` を除いて版にする。タグが無いリポジトリは `ref:<branch|sha>` で入れる。
- 所有の目印: リンクするスキルディレクトリに `.mise-skill`（中身は `install_path`）。リンク記録: `install_path/.mise-skill.json`。
- mise 2026.10.10 で動作確認した挙動に依存する（spec の「確認済みの前提」）。
- エラーメッセージは `mise-skill: ` で始める。
- コミットメッセージの末尾に `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>` を付ける。
- `kukv/structure` での作業（Task 1 / 8）では、コミットメッセージを `git commit -F <file>`、PR 本文を `gh pr create --body-file <file>` で渡す。structure の PreToolUse フックはコマンド全体の文字列を検査するため。

## File Structure

| ファイル | 責務 |
|---|---|
| `metadata.lua` | プラグイン名と版 |
| `hooks/backend_list_versions.lua` | タグ一覧 → 版一覧 |
| `hooks/backend_install.lua` | 取得・展開 → スキル選択 → リンク |
| `hooks/backend_uninstall.lua` | 自分のリンクを外す |
| `hooks/backend_exec_env.lua` | 空の環境を返す |
| `lib/github.lua` | タグ取得、版の正規化、ref 解決、tarball URL |
| `lib/skills.lua` | `SKILL.md` の発見、frontmatter の `name`、`skills` オプションでの選択 |
| `lib/targets.lua` | `agents` / `dirs` / `MISE_SKILL_AGENTS` からリンク先ディレクトリを決める |
| `lib/links.lua` | 目印・リンクの作成、所有判定、記録、解除 |
| `tests/lib.sh` | テスト共通処理（使い捨て HOME で mise を動かす） |
| `tests/versions.test.sh` | 版一覧 |
| `tests/install.test.sh` | 取得・展開・スキル選択・エラー |
| `tests/link.test.sh` | リンクの作成・張り替え・衝突・解除 |
| `.github/workflows/test.yml` | Linux / macOS でテスト |
| `README.md` | 使い方 |

テストはネットワークで GitHub 上の fixture リポジトリ `kukv/mise-skill-fixtures`（タグ無しの確認だけ `kukv/structure`）を使う。GitHub API のレート制限を避けるため、テスト実行時は `GITHUB_TOKEN`（または `MISE_GITHUB_TOKEN`）を環境に入れる。ローカルでは `GITHUB_TOKEN="$(gh auth token)" sh tests/xxx.test.sh`。

テストに使うリポジトリ:

| リポジトリ | 性質 |
|---|---|
| `kukv/mise-skill-fixtures` | タグ `v0.1.0` / `v0.2.0`（版でないタグ `draft-v9` も混ざる）。スキル `alpha` `beta`（`skills/`）と `gamma`（`nested/deep/gamma/`）。ブランチ `no-skills`（`SKILL.md` 無し）、`invalid-name`（不正な名前 `../../escape` のスキル入り） |
| `kukv/structure` | タグ無し、既定ブランチ `main`。スキル無し |

---

### Task 1: GitHub リポジトリ作成の PR（kukv/structure）

人のマージ待ちが発生するので最初に出しておき、待つ間に Task 2 以降を進める。

**Files:**
- Create: `~/dev/ghq/github.com/kukv/structure/terraform/repository_mise_skill.tf`

**Interfaces:**
- Produces: GitHub リポジトリ `kukv/mise-skill`（public、マージ後に作られる）

- [ ] **Step 1: structure のルールを読む**

`~/dev/ghq/github.com/kukv/structure/CLAUDE.md` と `.claude/skills/manage-repository/SKILL.md`、`terraform/modules/repository/variables.tf` を読む。禁止事項（`gh` による書き込み、ローカル plan/apply、`gh pr merge`）を守る。

- [ ] **Step 2: 作業ブランチを切る**

```bash
git -C ~/dev/ghq/github.com/kukv/structure switch main
git -C ~/dev/ghq/github.com/kukv/structure pull --ff-only
git -C ~/dev/ghq/github.com/kukv/structure switch -c add-mise-skill
```

- [ ] **Step 3: tf を書く**

`terraform/repository_mise_skill.tf`:

```hcl
module "repository_mise_skill" {
  source = "./modules/repository"

  name        = "mise-skill"
  visibility  = "public"
  description = "mise backend plugin that installs agent skills from GitHub and links them for Claude Code and Codex"
  topics      = ["mise", "mise-plugin", "agent-skills", "claude-code", "codex", "lua"]
}
```

ブランチ保護の必須チェックは、Task 8 で CI のジョブ名が決まってから別 PR で足す（1 PR = 1 目的）。

- [ ] **Step 4: 検証**

```bash
make -C ~/dev/ghq/github.com/kukv/structure fmt
terraform -chdir=$HOME/dev/ghq/github.com/kukv/structure/terraform init -backend=false -lockfile=readonly
terraform -chdir=$HOME/dev/ghq/github.com/kukv/structure/terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: コミット・push・PR**

コミットメッセージは `feat(terraform): mise-skill リポジトリを追加する`。`gh pr create` で PR を出す。本文の末尾に `🤖 Generated with [Claude Code](https://claude.com/claude-code)`。CI の plan コメントを確認し、マージはユーザーに依頼する（自分ではマージしない）。

---

### Task 2: 雛形・テスト基盤・版一覧

**Files:**
- Create: `metadata.lua`, `hooks/backend_exec_env.lua`, `hooks/backend_list_versions.lua`, `hooks/backend_install.lua`（仮）, `lib/github.lua`, `tests/lib.sh`, `tests/versions.test.sh`, `.gitignore`

**Interfaces:**
- Produces:
  - `github.tags(repo: string) -> string[]`（GitHub API の順のままのタグ名）
  - `github.versions(tags: string[]) -> string[]`（`v` を除き重複を除いた昇順）
  - `tests/lib.sh` の関数 `new_home <name>`、`m <mise args...>`、`config`（stdin を `$h/.config/mise/config.toml` に書く）、`fail <msg>`、変数 `$repo` `$h`

- [ ] **Step 1: テスト共通処理を書く**

`tests/lib.sh`:

```sh
# Shared helpers for the tests. Source it: . "$(dirname "$0")/lib.sh"
# Each test runs mise in a throwaway HOME with this checkout linked as the "skill" plugin.
# GITHUB_TOKEN / MISE_GITHUB_TOKEN are passed through so GitHub API calls are authenticated.
set -eu
repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
h=""

fail() { echo "FAIL: $*" >&2; exit 1; }

# m <args...>: run mise inside $h with no XDG / MISE_* overrides leaking in from the caller.
m() {
  (cd "$h/work" && env -u XDG_CONFIG_HOME -u XDG_DATA_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME \
    -u MISE_DATA_DIR -u MISE_CONFIG_DIR -u MISE_CACHE_DIR -u MISE_STATE_DIR -u MISE_ENV \
    -u MISE_SKILL_AGENTS MISE_CEILING_PATHS="$h" HOME="$h" MISE_YES=1 mise "$@")
}

# new_home <name>: make a fresh HOME under $tmp, make it current, link the plugin.
new_home() {
  h="$tmp/$1"
  mkdir -p "$h/.config/mise" "$h/work"
  m plugins link skill "$repo" >/dev/null
}

# config: write stdin as the global mise config of the current HOME.
config() { cat > "$h/.config/mise/config.toml"; }
```

- [ ] **Step 2: 失敗するテストを書く**

`tests/versions.test.sh`:

```sh
#!/bin/sh
# BackendListVersions: tags become versions without the leading "v"; a repo without tags errors.
. "$(dirname "$0")/lib.sh"

new_home versions
out="$(m ls-remote skill:example/writing-guide)"
echo "$out" | grep -qx '0.2.0' || fail "ls-remote should list 0.2.0, got: $out"
echo "$out" | grep -q '^v' && fail "versions must not start with v: $out"
[ "$(echo "$out" | head -n1)" = "0.1.0" ] || fail "versions must be oldest first, got: $out"
echo "$out" | grep -q 'draft-v9' && fail "non-version tags must be dropped: $out"
latest="$(m latest skill:example/writing-guide)"
echo "$latest" | grep -q '^[0-9]' || fail "latest should be a version, got: $latest"

if err="$(m ls-remote skill:example/code-search 2>&1)"; then
  fail "ls-remote on a repo without tags should fail"
fi
echo "$err" | grep -q 'ref:main' || fail "error should suggest ref:main, got: $err"

echo "ok versions"
```

- [ ] **Step 3: 実行して失敗を確認する**

Run: `GITHUB_TOKEN="$(gh auth token)" sh tests/versions.test.sh`
Expected: FAIL（プラグインのファイルが無いので `mise plugins link` か `ls-remote` が失敗する）

- [ ] **Step 4: 実装する**

`metadata.lua`:

```lua
PLUGIN = {
    name = "skill",
    version = "0.1.0",
    description = "Install agent skills from GitHub and link them for Claude Code and Codex",
    homepage = "https://github.com/kukv/mise-skill",
    license = "MIT",
}
```

`hooks/backend_exec_env.lua`:

```lua
-- Skills add nothing to the environment.
function PLUGIN:BackendExecEnv(ctx)
    return { env_vars = {} }
end
```

`hooks/backend_install.lua`（Task 3 で置き換える仮実装。mise は必須 hook が揃わないと読み込まない）:

```lua
function PLUGIN:BackendInstall(ctx)
    error("mise-skill: install is not implemented yet")
end
```

`lib/github.lua`:

```lua
local http = require("http")
local json = require("json")
local semver = require("semver")

local M = {}

-- api_get(path) -> decoded JSON. mise adds the GitHub token to api.github.com requests itself.
local function api_get(path)
    local url = "https://api.github.com" .. path
    local resp = http.get({ url = url, headers = { ["Accept"] = "application/vnd.github+json" } })
    if resp.status_code == 404 then
        error("mise-skill: GitHub returned 404 for " .. url .. " (does the repository exist?)")
    elseif resp.status_code ~= 200 then
        error("mise-skill: GET " .. url .. " failed: HTTP " .. resp.status_code)
    end
    return json.decode(resp.body)
end

-- tags(repo) -> every tag name of owner/repo, in GitHub's order.
function M.tags(repo)
    local names = {}
    local page = 1
    while true do
        local batch = api_get("/repos/" .. repo .. "/tags?per_page=100&page=" .. page)
        for _, tag in ipairs(batch) do
            table.insert(names, tag.name)
        end
        if #batch < 100 then
            break
        end
        page = page + 1
    end
    return names
end

-- versions(tags) -> version-like tag names (a digit after an optional "v") without the "v",
-- deduplicated, oldest first. Other tags such as "draft-v9" are not versions: semver.sort
-- would read their digits and put them last, making them "latest".
function M.versions(tags)
    local seen, out = {}, {}
    for _, tag in ipairs(tags) do
        local version = (tag:gsub("^v", ""))
        if version:match("^%d") and not seen[version] then
            seen[version] = true
            table.insert(out, version)
        end
    end
    return semver.sort(out)
end

return M
```

`hooks/backend_list_versions.lua`:

```lua
local github = require("github")

-- Versions are the repository's tags. A repository without tags can only be installed by ref
-- ("ref:main"); mise does not call this hook for ref: versions.
function PLUGIN:BackendListVersions(ctx)
    local versions = github.versions(github.tags(ctx.tool))
    if #versions == 0 then
        error('mise-skill: ' .. ctx.tool .. ' has no tags; pin a branch or commit instead, e.g. "ref:main"')
    end
    return { versions = versions }
end
```

`.gitignore`:

```
.DS_Store
```

- [ ] **Step 5: 実行して通ることを確認する**

Run: `GITHUB_TOKEN="$(gh auth token)" sh tests/versions.test.sh`
Expected: `ok versions`

- [ ] **Step 6: コミット**

```bash
git add metadata.lua hooks lib tests .gitignore
git commit -m "feat: タグを版として返す backend plugin の雛形を作る"
```

---

### Task 3: 取得・展開とスキルの選択

**Files:**
- Create: `lib/skills.lua`, `tests/install.test.sh`
- Modify: `lib/github.lua`（`ref_for` と `tarball_url` を追加）, `hooks/backend_install.lua`（置き換え）

**Interfaces:**
- Consumes: `github.tags(repo)`（Task 2）
- Produces:
  - `github.ref_for(repo: string, version: string) -> string`（`ref:x` → `x`、版 → 実際のタグ名）
  - `github.tarball_url(repo: string, ref: string) -> string`
  - `skills.parse_name(text: string) -> string|nil`
  - `skills.discover(root: string) -> {name: string, dir: string}[]`（パス順）
  - `skills.select(found, wanted: string[]|string|nil) -> {name, dir}[]`

- [ ] **Step 1: 失敗するテストを書く**

`tests/install.test.sh`:

```sh
#!/bin/sh
# BackendInstall: fetch a tag or ref into install_path and select skills.
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }

new_home install
echo '[tools]' | config

# a tagged version, with or without the "v" in the tag
m install skill:example/writing-guide@0.2.0 >/dev/null 2>&1 || fail "install writing-guide@0.2.0"
[ -f "$(installs)/skill-example-writing-guide/0.2.0/skills/writing-guide/SKILL.md" ] ||
  fail "writing-guide SKILL.md should be extracted"

# a ref on a repository without tags
m install skill:example/code-search@ref:main >/dev/null 2>&1 || fail "install code-search@ref:main"
[ -f "$(installs)/skill-example-code-search/ref-main/code-search/skills/outline/SKILL.md" ] ||
  fail "code-search should be extracted"

# no SKILL.md at all
if err="$(m install skill:example/no-skills@ref:main 2>&1)"; then
  fail "a repository without SKILL.md should fail"
fi
echo "$err" | grep -q 'no SKILL.md' || fail "error should say no SKILL.md, got: $err"

# skills option names a skill that does not exist
printf '[tools]\n"skill:example/prose-lint" = { version = "latest", skills = ["nope"] }\n' | config
if err="$(m install 2>&1)"; then
  fail "an unknown name in skills should fail"
fi
echo "$err" | grep -q 'nope' || fail "error should name the unknown skill, got: $err"

# an unknown version
if m install skill:example/writing-guide@0.0.0-nope >/dev/null 2>&1; then
  fail "an unknown version should fail"
fi

echo "ok install"
```

- [ ] **Step 2: 実行して失敗を確認する**

Run: `GITHUB_TOKEN="$(gh auth token)" sh tests/install.test.sh`
Expected: FAIL `install writing-guide@0.2.0`（仮実装が error を投げる）

- [ ] **Step 3: `lib/github.lua` に追加する**

`return M` の直前に追加:

```lua
-- ref_for(repo, version) -> the git ref to download. "ref:<x>" is used as is; a version is
-- matched against the tags with or without a leading "v".
function M.ref_for(repo, version)
    if version:sub(1, 4) == "ref:" then
        return version:sub(5)
    end
    for _, tag in ipairs(M.tags(repo)) do
        if tag == version or tag == "v" .. version then
            return tag
        end
    end
    error("mise-skill: " .. repo .. " has no tag " .. version .. " or v" .. version)
end

-- tarball_url(repo, ref) -> the source tarball. No token: codeload.github.com rejects it.
function M.tarball_url(repo, ref)
    return "https://codeload.github.com/" .. repo .. "/tar.gz/" .. ref
end
```

- [ ] **Step 4: `lib/skills.lua` を書く**

```lua
local file = require("file")

local M = {}

-- parse_name(text) -> the "name:" value of a SKILL.md front matter, or nil.
function M.parse_name(text)
    local front = text:match("^%-%-%-\r?\n(.-)\r?\n%-%-%-")
    if front == nil then
        return nil
    end
    for line in front:gmatch("[^\r\n]+") do
        local value = line:match("^name:%s*(.-)%s*$")
        if value ~= nil then
            value = (value:gsub("^[\"'](.*)[\"']$", "%1"))
            if value ~= "" then
                return value
            end
            return nil
        end
    end
    return nil
end

-- discover(root) -> every skill under root as { name, dir }, where dir holds SKILL.md.
function M.discover(root)
    local found = {}
    for _, path in ipairs(file.glob(file.join_path(root, "**", "SKILL.md"))) do
        local name = M.parse_name(file.read(path))
        if name ~= nil then
            table.insert(found, { name = name, dir = path:sub(1, #path - #"/SKILL.md") })
        end
    end
    if #found == 0 then
        error("mise-skill: no SKILL.md with a name was found in " .. root)
    end
    return found
end

-- select(found, wanted) -> the skills to link. wanted is the skills tool option: nil means
-- all of them, a string means one. Unknown and ambiguous names fail.
function M.select(found, wanted)
    local by_name, order = {}, {}
    for _, skill in ipairs(found) do
        if by_name[skill.name] == nil then
            by_name[skill.name] = {}
            table.insert(order, skill.name)
        end
        table.insert(by_name[skill.name], skill)
    end
    if type(wanted) == "string" then
        wanted = { wanted }
    end
    local names = wanted or order
    local selected = {}
    for _, name in ipairs(names) do
        local matches = by_name[name]
        if matches == nil then
            error("mise-skill: no skill named " .. name .. " (found: " .. table.concat(order, ", ") .. ")")
        elseif #matches > 1 then
            local dirs = {}
            for _, skill in ipairs(matches) do
                table.insert(dirs, skill.dir)
            end
            error("mise-skill: more than one skill is named " .. name .. ": " .. table.concat(dirs, ", "))
        end
        table.insert(selected, matches[1])
    end
    return selected
end

return M
```

- [ ] **Step 5: `hooks/backend_install.lua` を置き換える**

```lua
local archiver = require("archiver")
local file = require("file")
local http = require("http")
local github = require("github")
local skills = require("skills")

function PLUGIN:BackendInstall(ctx)
    local ref = github.ref_for(ctx.tool, ctx.version)
    local archive = file.join_path(ctx.download_path, "source.tar.gz")
    http.download_file({ url = github.tarball_url(ctx.tool, ref) }, archive)
    archiver.decompress(archive, ctx.install_path, { strip_components = 1 })

    skills.select(skills.discover(ctx.install_path), ctx.options.skills)
    return {}
end
```

- [ ] **Step 6: 実行して通ることを確認する**

Run: `GITHUB_TOKEN="$(gh auth token)" sh tests/install.test.sh && GITHUB_TOKEN="$(gh auth token)" sh tests/versions.test.sh`
Expected: `ok install` と `ok versions`

- [ ] **Step 7: コミット**

```bash
git add lib/github.lua lib/skills.lua hooks/backend_install.lua tests/install.test.sh
git commit -m "feat: タグか ref の tarball を展開し、skills オプションでスキルを選ぶ"
```

---

### Task 4: リンク先の決定とリンクの作成

**Files:**
- Create: `lib/targets.lua`, `lib/links.lua`, `tests/link.test.sh`
- Modify: `hooks/backend_install.lua`

**Interfaces:**
- Consumes: `skills.select(...)`（Task 3、`{name, dir}[]`）
- Produces:
  - `targets.AGENTS: table<string, string>`（エージェント名 → `$HOME` からの相対パス）
  - `targets.resolve(options: table, env_agents: string|nil, home: string) -> string[]`（重複を除いた絶対パス、指定順）
  - `links.MARKER = ".mise-skill"`、`links.RECORD = ".mise-skill.json"`
  - `links.classify(path: string) -> "missing"|"dangling"|"ours"|"foreign", owner: string|nil`
  - `links.install(install_path: string, tmpdir: string, selected: {name, dir}[], dirs: string[])`

- [ ] **Step 1: 失敗するテストを書く**

`tests/link.test.sh`:

```sh
#!/bin/sh
# Linking: where links go, what they point at, and what is left alone.
. "$(dirname "$0")/lib.sh"
installs() { echo "$h/.local/share/mise/installs"; }

# default agent: claude-code only
new_home default
printf '[tools]\n"skill:example/writing-guide" = "0.2.0"\n' | config
m install >/dev/null 2>&1 || fail "default: install"
[ -L "$h/.claude/skills/writing-guide" ] || fail "default: link in ~/.claude/skills"
[ -f "$h/.claude/skills/writing-guide/SKILL.md" ] || fail "default: link should reach SKILL.md"
[ "$(cat "$h/.claude/skills/writing-guide/.mise-skill")" = "$(installs)/skill-example-writing-guide/0.2.0" ] ||
  fail "default: marker should hold install_path"
[ -e "$h/.agents/skills/writing-guide" ] && fail "default: codex is not a default agent"

# MISE_SKILL_AGENTS from [env], creating ~/.agents/skills that does not exist yet
new_home env
printf '[env]\nMISE_SKILL_AGENTS = "claude-code,codex"\n[tools]\n"skill:example/writing-guide" = "0.2.0"\n' | config
m install >/dev/null 2>&1 || fail "env: install"
[ -L "$h/.claude/skills/writing-guide" ] || fail "env: claude-code link"
[ -L "$h/.agents/skills/writing-guide" ] || fail "env: codex link"

# agents option overrides MISE_SKILL_AGENTS; dirs adds a path; skills selects
new_home options
cat <<'EOT' | config
[env]
MISE_SKILL_AGENTS = "claude-code,codex"
[tools]
"skill:example/code-search" = { version = "ref:main", skills = ["code-search-outline"], agents = ["codex"], dirs = ["~/extra/skills"] }
EOT
m install >/dev/null 2>&1 || fail "options: install"
[ -L "$h/.agents/skills/code-search-outline" ] || fail "options: codex link"
[ -L "$h/extra/skills/code-search-outline" ] || fail "options: dirs link"
[ -e "$h/.claude/skills/code-search-outline" ] && fail "options: agents should replace the env default"
[ -e "$h/.agents/skills/code-search" ] && fail "options: skills should select only code-search-outline"

# unknown agent and relative dirs fail the install
new_home bad
printf '[tools]\n"skill:example/writing-guide" = { version = "0.2.0", agents = ["nope"] }\n' | config
if err="$(m install 2>&1)"; then fail "bad: unknown agent should fail"; fi
echo "$err" | grep -q 'unknown agent nope' || fail "bad: error should name the agent, got: $err"
printf '[tools]\n"skill:example/writing-guide" = { version = "0.2.0", dirs = ["relative/skills"] }\n' | config
if err="$(m install 2>&1)"; then fail "bad: relative dirs should fail"; fi
echo "$err" | grep -q 'relative/skills' || fail "bad: error should name the dir, got: $err"

# a real directory with the same name is left alone
new_home conflict
mkdir -p "$h/.claude/skills/writing-guide"
echo mine > "$h/.claude/skills/writing-guide/SKILL.md"
printf '[tools]\n"skill:example/writing-guide" = "0.2.0"\n' | config
m install >/dev/null 2>&1 || fail "conflict: install should still succeed"
[ -L "$h/.claude/skills/writing-guide" ] && fail "conflict: the real directory must not be replaced"
[ "$(cat "$h/.claude/skills/writing-guide/SKILL.md")" = mine ] || fail "conflict: contents changed"

# a dangling link with the same name is replaced
new_home dangling
mkdir -p "$h/.claude/skills"
ln -s "$h/gone" "$h/.claude/skills/writing-guide"
printf '[tools]\n"skill:example/writing-guide" = "0.2.0"\n' | config
m install >/dev/null 2>&1 || fail "dangling: install"
[ -f "$h/.claude/skills/writing-guide/SKILL.md" ] || fail "dangling: link should be replaced"

# a failed install (typo in skills) does not leave a version that plain `mise install` skips
new_home typo
printf '[tools]\n"skill:example/writing-guide" = { version = "0.2.0", skills = ["writing-guid"] }\n' | config
m install >/dev/null 2>&1 && fail "typo: install should fail"
printf '[tools]\n"skill:example/writing-guide" = { version = "0.2.0", skills = ["writing-guide"] }\n' | config
m install >/dev/null 2>&1 || fail "typo: install after the fix"
[ -L "$h/.claude/skills/writing-guide" ] || fail "typo: plain mise install after the fix should link"

echo "ok link"
```

- [ ] **Step 2: 実行して失敗を確認する**

Run: `GITHUB_TOKEN="$(gh auth token)" sh tests/link.test.sh`
Expected: FAIL `default: link in ~/.claude/skills`

- [ ] **Step 3: `lib/targets.lua` を書く**

```lua
local file = require("file")

local M = {}

-- Where each agent reads user-level skills, relative to $HOME.
M.AGENTS = {
    ["claude-code"] = ".claude/skills",
    ["codex"] = ".agents/skills",
}

local function as_list(value)
    if value == nil then
        return nil
    elseif type(value) == "string" then
        return { value }
    end
    return value
end

local function expand(path, home)
    if path == "~" then
        return home
    elseif path:sub(1, 2) == "~/" then
        return file.join_path(home, path:sub(3))
    elseif path:sub(1, 1) == "/" then
        return path
    end
    error("mise-skill: dirs entries must be absolute or start with ~/: " .. path)
end

-- resolve(options, env_agents, home) -> the directories to link into, deduplicated, in order:
-- the agents (options.agents, else MISE_SKILL_AGENTS, else claude-code), then options.dirs.
function M.resolve(options, env_agents, home)
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
        add(file.join_path(home, rel))
    end
    for _, dir in ipairs(as_list(options.dirs) or {}) do
        add(expand(dir, home))
    end
    return dirs
end

return M
```

- [ ] **Step 4: `lib/links.lua` を書く**

```lua
local file = require("file")
local json = require("json")
local log = require("log")

local M = {}

M.MARKER = ".mise-skill" -- in each linked skill dir; holds the install_path that owns it
M.RECORD = ".mise-skill.json" -- in install_path; the links this version placed

local function write(path, text)
    local f = assert(io.open(path, "w"))
    f:write(text)
    f:close()
end

-- classify(path) -> "missing", "dangling", "ours" with the owning install_path, or "foreign".
-- file.stat cannot read a link's target, so ownership is the marker seen through the link.
-- A dangling link (its target is gone) is replaceable: it serves no agent, and it is what a
-- mise-skill link becomes when its install directory is deleted by hand.
function M.classify(path)
    local st = file.stat(path)
    if st == nil then
        return "missing", nil
    end
    if st.is_symlink then
        if not file.exists(path) then
            return "dangling", nil
        end
        local marker = file.join_path(path, M.MARKER)
        if file.exists(marker) then
            return "ours", file.read(marker)
        end
    end
    return "foreign", nil
end

-- place(src, dst, tmpdir): point dst at src. file.symlink fails when dst's parent is missing,
-- but file.move creates parents and renames over an existing link, so build the link in tmpdir.
local counter = 0
local function place(src, dst, tmpdir)
    counter = counter + 1
    local tmp = file.join_path(tmpdir, "mise-skill-link-" .. counter)
    file.symlink(src, tmp)
    file.move(tmp, dst)
end

-- install(install_path, tmpdir, selected, dirs): mark each selected skill as owned by
-- install_path, link it into every dir, and record the links that were placed.
function M.install(install_path, tmpdir, selected, dirs)
    local placed = {}
    for _, skill in ipairs(selected) do
        write(file.join_path(skill.dir, M.MARKER), install_path)
        for _, dir in ipairs(dirs) do
            local dst = file.join_path(dir, skill.name)
            if M.classify(dst) == "foreign" then
                log.warn("mise-skill: skipped " .. dst .. ": it exists and mise-skill did not create it")
            else
                local ok, err = pcall(place, skill.dir, dst, tmpdir)
                if ok then
                    table.insert(placed, dst)
                else
                    log.warn("mise-skill: could not link " .. dst .. ": " .. tostring(err))
                end
            end
        end
    end
    write(file.join_path(install_path, M.RECORD), json.encode(placed))
end

return M
```

- [ ] **Step 5: `hooks/backend_install.lua` からリンクを呼ぶ**

ファイル全体を次にする:

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
    local dirs = targets.resolve(ctx.options, os.getenv("MISE_SKILL_AGENTS"), os.getenv("HOME"))

    local ref = github.ref_for(ctx.tool, ctx.version)
    local archive = file.join_path(ctx.download_path, "source.tar.gz")
    http.download_file({ url = github.tarball_url(ctx.tool, ref) }, archive)
    archiver.decompress(archive, ctx.install_path, { strip_components = 1 })

    local selected = skills.select(skills.discover(ctx.install_path), ctx.options.skills)
    links.install(ctx.install_path, ctx.download_path, selected, dirs)
    return {}
end
```

- [ ] **Step 6: 実行して通ることを確認する**

Run: `for t in tests/*.test.sh; do GITHUB_TOKEN="$(gh auth token)" sh "$t" || exit 1; done`
Expected: `ok install`、`ok link`、`ok versions`

`typo:` のケースが失敗した場合（mise が展開済みの `install_path` を残し、次の `mise install` が入れ済みとして飛ばす場合）は、`hooks/backend_install.lua` を「`download_path` 配下に展開して選択まで済ませ、成功してから `install_path` へ移す」形に変える。展開とスキル選択の部分を次に置き換える:

```lua
    -- Extract and select outside install_path, so a bad option leaves no half-installed version.
    local staging = file.join_path(ctx.download_path, "source")
    archiver.decompress(archive, staging, { strip_components = 1 })
    skills.select(skills.discover(staging), ctx.options.skills)
    for _, entry in ipairs(file.list(staging)) do
        file.move(entry, file.join_path(ctx.install_path, entry:sub(#staging + 2)))
    end
    local selected = skills.select(skills.discover(ctx.install_path), ctx.options.skills)
```

それでも失敗するなら、README の「Keeping links in sync」に「install が失敗したら `mise install -f` でやり直す」と書いてテストを `install -f` に変え、spec にも同じ制約を書き足す。

`upgrade:` 系（Task 5）や `options:` で既存リンクの張り替えが失敗する場合（`file.move` が既存の symlink を rename で置き換えられない場合）は、`M.install` の `place` 呼び出しの前に、`classify` が `ours` か `dangling` を返したときだけ `os.remove(dst)` する。

- [ ] **Step 7: コミット**

```bash
git add lib/targets.lua lib/links.lua hooks/backend_install.lua tests/link.test.sh
git commit -m "feat: install 時に agents / dirs へスキルの symlink を張る"
```

---

### Task 5: 張り替えとリンク解除

**Files:**
- Create: `hooks/backend_uninstall.lua`
- Modify: `lib/links.lua`（`uninstall` を追加）, `tests/link.test.sh`（ケース追加）

**Interfaces:**
- Consumes: `links.classify`, `links.RECORD`（Task 4）
- Produces: `links.uninstall(install_path: string)`

- [ ] **Step 1: 失敗するテストを足す**

`tests/link.test.sh` の `echo "ok link"` の直前に追加:

```sh
# upgrading relinks to the new version; removing the old version keeps the new link
new_home upgrade
printf '[tools]\n"skill:example/writing-guide" = "0.1.0"\n' | config
m install >/dev/null 2>&1 || fail "upgrade: install 0.1.0"
printf '[tools]\n"skill:example/writing-guide" = "0.2.0"\n' | config
m install >/dev/null 2>&1 || fail "upgrade: install 0.2.0"
[ "$(cat "$h/.claude/skills/writing-guide/.mise-skill")" = "$(installs)/skill-example-writing-guide/0.2.0" ] ||
  fail "upgrade: link should point at 0.2.0"
m uninstall skill:example/writing-guide@0.1.0 >/dev/null 2>&1 || fail "upgrade: uninstall 0.1.0"
[ -L "$h/.claude/skills/writing-guide" ] || fail "upgrade: removing 0.1.0 must keep the 0.2.0 link"

# install -f applies changed options and drops links that are no longer wanted
cat <<'EOT' | config
[tools]
"skill:example/writing-guide" = { version = "0.2.0", agents = ["claude-code", "codex"] }
EOT
m install -f skill:example/writing-guide@0.2.0 >/dev/null 2>&1 || fail "reinstall: add codex"
[ -L "$h/.agents/skills/writing-guide" ] || fail "reinstall: codex link should appear"
cat <<'EOT' | config
[tools]
"skill:example/writing-guide" = { version = "0.2.0", agents = ["codex"] }
EOT
m install -f skill:example/writing-guide@0.2.0 >/dev/null 2>&1 || fail "reinstall: drop claude-code"
[ -e "$h/.claude/skills/writing-guide" ] && fail "reinstall: claude-code link should be gone"
[ -L "$h/.agents/skills/writing-guide" ] || fail "reinstall: codex link should stay"

# removing the tool from the config and pruning removes its links, and only its links
mkdir -p "$h/.agents/skills/handmade"
echo '[tools]' | config
m prune >/dev/null 2>&1 || fail "prune"
[ -e "$h/.agents/skills/writing-guide" ] && fail "prune: link should be gone"
[ -d "$h/.agents/skills/handmade" ] || fail "prune: other entries must stay"
```

- [ ] **Step 2: 実行して失敗を確認する**

Run: `GITHUB_TOKEN="$(gh auth token)" sh tests/link.test.sh`
Expected: FAIL `reinstall: claude-code link should be gone`（uninstall hook がまだ無いので古いリンクが残る）

- [ ] **Step 3: `lib/links.lua` に `uninstall` を追加する**

`return M` の直前に追加:

```lua
-- uninstall(install_path): remove the links this version recorded that still point at it.
-- ctx.options is unreliable here (defaults only during prune), so use the record.
-- After an upgrade the old version is removed later; its links already point elsewhere.
function M.uninstall(install_path)
    local record = file.join_path(install_path, M.RECORD)
    if not file.exists(record) then
        return
    end
    for _, dst in ipairs(json.decode(file.read(record))) do
        local kind, owner = M.classify(dst)
        if kind == "ours" and owner == install_path then
            local ok, err = os.remove(dst)
            if not ok then
                log.warn("mise-skill: could not remove " .. dst .. ": " .. tostring(err))
            end
        end
    end
end
```

- [ ] **Step 4: `hooks/backend_uninstall.lua` を書く**

```lua
local links = require("links")

function PLUGIN:BackendUninstall(ctx)
    links.uninstall(ctx.install_path)
end
```

- [ ] **Step 5: 実行して通ることを確認する**

Run: `for t in tests/*.test.sh; do GITHUB_TOKEN="$(gh auth token)" sh "$t" || exit 1; done`
Expected: `ok install`、`ok link`、`ok versions`

- [ ] **Step 6: コミット**

```bash
git add lib/links.lua hooks/backend_uninstall.lua tests/link.test.sh
git commit -m "feat: uninstall で自分が張ったリンクだけを外す"
```

---

### Task 6: README

**Files:**
- Create: `README.md`, `LICENSE`

- [ ] **Step 1: README を書く**

`README.md`（英語。公開リポジトリのため）:

````markdown
# mise-skill

A [mise](https://mise.jdx.dev) backend plugin that installs [agent skills](https://agentskills.io)
from GitHub repositories and links them where Claude Code and Codex look for them.

```sh
mise plugins install skill https://github.com/kukv/mise-skill
```

```toml
# ~/.config/mise/config.toml
[env]
MISE_SKILL_AGENTS = "claude-code,codex"   # default: claude-code

[tools]
"skill:example/writing-guide" = "latest"
"skill:example/prose-lint" = { version = "latest", agents = ["claude-code"] }
"skill:example/code-search" = { version = "ref:main", skills = ["code-search", "code-search-outline"] }
"skill:foo/bar" = { version = "latest", dirs = ["~/somewhere/skills"] }
```

```sh
mise install
```

Each skill is extracted under mise's installs directory and symlinked as
`<dir>/<skill name>`. Nothing else is needed: no hooks, no extra tools.

## Versions

Versions are the repository's tags without a leading `v`. A repository without tags is
installed by ref: `"ref:main"` or `"ref:<commit>"`.

## Options

| Option | Default | Meaning |
|---|---|---|
| `skills` | every skill found | Skill names (the `name:` in `SKILL.md`) to link |
| `agents` | `MISE_SKILL_AGENTS`, else `claude-code` | Agents to link for |
| `dirs` | none | Extra directories (absolute or `~/...`) to link into |

| Agent | Directory |
|---|---|
| `claude-code` | `~/.claude/skills` |
| `codex` | `~/.agents/skills` |

## Keeping links in sync

Links are made when a version is installed and removed when it is uninstalled.

| To | Run |
|---|---|
| add a skill or move to a new version | `mise install` / `mise upgrade` |
| apply changed `skills` / `agents` / `dirs` | `mise install -f skill:owner/repo` |
| remove a skill's links | delete it from `[tools]`, then `mise prune` |

An existing directory or a link that mise-skill did not create is never touched; the install
warns and skips it.

## Development

```sh
for t in tests/*.test.sh; do GITHUB_TOKEN="$(gh auth token)" sh "$t" || exit 1; done
```

Tested with mise 2026.10.10 on Linux and macOS.
````

- [ ] **Step 2: LICENSE を置く**

MIT ライセンスの全文を `LICENSE` に書く（著作権者 `kukv`、年 `2026`）。

- [ ] **Step 3: コミット**

```bash
git add README.md LICENSE
git commit -m "docs: README と LICENSE を追加する"
```

---

### Task 7: push と CI

Task 1 の PR がマージされ、`kukv/mise-skill` ができてから行う。

**Files:**
- Create: `.github/workflows/test.yml`

- [ ] **Step 1: リポジトリができたことを確かめる**

Run: `gh repo view kukv/mise-skill --json name,visibility`
Expected: `{"name":"mise-skill","visibility":"PUBLIC"}`

- [ ] **Step 2: CI を書く**

`.github/workflows/test.yml`:

```yaml
name: test

on:
  pull_request:
  push:
    branches: [main]

permissions:
  contents: read

jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
        with:
          version: 2026.10.10
          install: false
      - name: Run tests
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: for t in tests/*.test.sh; do sh "$t" || exit 1; done
```

実装時に `actions/checkout` と `jdx/mise-action` の最新のメジャー版を確認し、他の kukv リポジトリ（例: dotfiles の `.github/workflows`）が SHA 固定しているならそれに合わせる。

- [ ] **Step 3: コミットして push**

```bash
git add .github/workflows/test.yml
git commit -m "ci: Linux と macOS でテストを回す"
git remote add origin git@github.com:kukv/mise-skill.git
git push -u origin main
```

- [ ] **Step 4: CI を確認する**

Run: `gh run list -R kukv/mise-skill --limit 1` → `gh run watch -R kukv/mise-skill <run-id>`
Expected: `test (ubuntu-latest)` と `test (macos-latest)` が成功。macOS で失敗したら `gh run view --log-failed` で原因を読み、修正して push する。

- [ ] **Step 5: タグを打つ**

```bash
git tag v0.1.0
git push origin v0.1.0
```

---

### Task 8: structure にブランチ保護の必須チェックを足す

Task 7 の CI が通ってから。Task 1 と同じく structure の `manage-repository` スキルに従う。

**Files:**
- Modify: `~/dev/ghq/github.com/kukv/structure/terraform/repository_mise_skill.tf`

- [ ] **Step 1: ブランチを切って必須チェックを足す**

```bash
git -C ~/dev/ghq/github.com/kukv/structure switch main
git -C ~/dev/ghq/github.com/kukv/structure pull --ff-only
git -C ~/dev/ghq/github.com/kukv/structure switch -c mise-skill-required-checks
```

`module "repository_mise_skill"` に追加:

```hcl
  default_branch_protection = {
    required_status_checks = [
      { context = "test (ubuntu-latest)" },
      { context = "test (macos-latest)" },
    ]
  }
```

- [ ] **Step 2: 検証して PR を出す**

```bash
make -C ~/dev/ghq/github.com/kukv/structure fmt
terraform -chdir=$HOME/dev/ghq/github.com/kukv/structure/terraform init -backend=false -lockfile=readonly
terraform -chdir=$HOME/dev/ghq/github.com/kukv/structure/terraform validate
```

コミットメッセージは `feat(terraform): mise-skill の main に必須チェックを設定する`。`gh pr create` で PR を出し、マージはユーザーに依頼する。

---

### Task 9: dotfiles への移行

プラグインの v0.1.0 が出てから、dotfiles の別ブランチ・別 PR で行う。

**Files:**
- Modify: `~/dev/ghq/github.com/kukv/dotfiles/mise.toml`（プラグイン・`[tools]`・`[env]`。`npm:skills` を外す）
- Modify: `~/dev/ghq/github.com/kukv/dotfiles/bootstrap/post-tools.sh`（スキル用ループを削除）
- Modify: dotfiles の移行手順ドキュメント（`docs/` 配下の該当ファイル）
- Modify: メモリ `claude-skills-provisioning.md`

- [ ] **Step 1: 現状を読む**

`npm:skills` を宣言しているのが、実際にグローバル設定として配置される mise config（`~/.config/mise/config.toml` に入るもの）かどうかを確かめる。`skill:*` のツールと `MISE_SKILL_AGENTS` は同じ配置先の config に置く（hook がその `[env]` を読むため）。あわせて `mise.toml` の `[tools]` で `npm:skills` を宣言している場所と、プラグインの宣言方法（mise config の `[plugins]`）を確認する。`bootstrap/post-tools.sh` のスキル用ループ（`# Claude Code skills:` から `EOT` まで）を確認する。

- [ ] **Step 2: mise config を書き換える**

`[plugins]` に追加:

```toml
skill = "https://github.com/kukv/mise-skill"
```

`[env]` に追加:

```toml
MISE_SKILL_AGENTS = "claude-code"
```

`[tools]` に追加（`npm:skills` の行は削除）:

```toml
"skill:example/tool-a" = { version = "latest", skills = ["tool-a"] }
"skill:example/tool-c" = { version = "latest", skills = ["tool-c"] }
"skill:example/tool-b" = { version = "latest", skills = ["tool-b"] }
"skill:example/code-search" = { version = "ref:main", skills = ["code-search", "code-search-outline"] }
"skill:example/writing-guide" = "latest"
"skill:example/prose-lint" = "latest"
```

`tool-a` / `tool-b` / `tool-c` はツール本体のリポジトリなので `skills` で明示する。各リポジトリのスキル名は、Step 4 の install 後に `~/.claude/skills` を見て確認する。

- [ ] **Step 3: `bootstrap/post-tools.sh` のスキル用ループを削除する**

`# Claude Code skills: "<skill> <repo>". ...` のコメントから、そのヒアドキュメントの `EOT` までを削除する。自作スキルに関するコメントは、自作スキルのディレクトリが mise `[dotfiles]` で配置される旨として `mise.toml` 側に必要なら移す。

- [ ] **Step 4: このマシンで移行する**

```bash
rm -rf ~/.claude/skills/{tool-a,tool-c,tool-b,code-search,code-search-outline,writing-guide,prose-lint}
rm -rf ~/.agents/skills/{tool-a,tool-c} ~/.agents/.skill-lock.json
mise install
ls -la ~/.claude/skills
```

Expected: 7 つが symlink で並び、自作スキルのディレクトリ（実ディレクトリ）と自作 symlink は変わらない。

- [ ] **Step 5: dotfiles のテストを回す**

Run: `sh tests/bootstrap/dotfiles.test.sh`（ほかに `tests/bootstrap/*.test.sh` があれば全部）
Expected: 全部成功

- [ ] **Step 6: 移行手順をドキュメントに書く**

dotfiles の `docs/` にある移行手順ファイル（WSL / Mac）に、Step 4 の削除コマンドと `mise install` を追記する。

- [ ] **Step 7: メモリを更新する**

`/home/tech/.claude/projects/-home-tech-dev-ghq-github-com-kukv-dotfiles/memory/claude-skills-provisioning.md` を、mise-skill プラグインで `[tools]` に宣言する方式に書き換える（追加方法: `[tools]` に `"skill:owner/repo"` を足して `mise install`。設定変更は `install -f`、削除は外して `mise prune`）。

- [ ] **Step 8: コミット・PR**

コミットメッセージは `feat(bootstrap): スキルを mise-skill プラグインで管理する`。`gh pr create` で PR を出す（本文末尾に `🤖 Generated with [Claude Code](https://claude.com/claude-code)`）。
