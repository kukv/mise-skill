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
