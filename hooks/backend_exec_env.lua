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
        local reason = tostring(err):gsub("^mise%-skill: ", "")
        log.warn("mise-skill: could not link " .. ctx.tool .. ": " .. reason)
    end
    return { env_vars = {} }
end
