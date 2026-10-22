local file = require("file")
local json = require("json")
local log = require("log")

local M = {}

-- Where each agent reads skills, relative to a base: $HOME for the global config, the root option
-- for a project.
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
    error("mise-skill: " .. what .. " must be absolute or start with ~/: " .. path, 0)
end

-- requested(flags, install_path) -> the tool name and entry in `mise ls --json <flags>`, run
-- where mise was started, whose install_path is install_path; nil when none is. Raises when
-- mise cannot be run or its output is not JSON.
-- Nothing in ctx tells which config a hook was called for, but `mise ls` does.
local function requested(flags, install_path)
    local p = io.popen("mise ls --json " .. flags .. " 2>/dev/null </dev/null")
    if p == nil then
        error("could not run mise ls", 0)
    end
    local out = p:read("*a")
    p:close()
    local ok, tools = pcall(json.decode, out)
    if not ok or type(tools) ~= "table" then
        error("could not read the output of mise ls --json " .. flags, 0)
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
-- hooks for every installed version, with the options of the version in effect, and `mise use`
-- installs before it writes the config. options.root wins; without it the config must be global.
-- root is expanded first, so a relative one fails `mise use` at install time too.
-- A project config without root raises: ExecEnv results are cached per install and options, so a
-- quiet nil here would stop a global config with the same options from ever being linked.
-- When mise ls fails it warns and returns nil.
function M.base(install_path, options, home)
    local root = options.root ~= nil and expand(options.root, home, "root") or nil
    local ok, found = pcall(function()
        local name, entry = requested("--current", install_path)
        if name == nil then
            return nil
        end
        local global = root == nil and requested("--current --global", install_path) ~= nil
        return { name = name, entry = entry, global = global }
    end)
    if not ok then
        log.warn("mise-skill: could not tell which config uses " .. install_path .. ": " .. tostring(found))
        return nil
    elseif found == nil then
        return nil
    elseif root ~= nil then
        return root
    elseif found.global then
        return home
    end
    local source = found.entry.source and found.entry.source.path or "a project config"
    error(
        "mise-skill: "
            .. found.name
            .. " is declared in "
            .. tostring(source)
            .. " "
            .. M.NO_ROOT
            .. ' = "{{config_root}}"',
        0
    )
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
            error("mise-skill: unknown agent " .. name .. " (known: claude-code, codex)", 0)
        end
        add(file.join_path(base, rel))
    end
    for _, dir in ipairs(as_list(options.dirs) or {}) do
        add(expand(dir, home, "dirs entries"))
    end
    return dirs
end

return M
