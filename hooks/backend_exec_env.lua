local links = require("links")
local log = require("log")
local skills = require("skills")
local targets = require("targets")

-- BackendInstall runs once per version, but this runs for each config that uses the version
-- (mise caches the result per install and options), so a project with root = "{{config_root}}"
-- is linked even when the version was installed for another project. Without root the
-- directories are shared in $HOME, and configs that resolve different versions of the tool would
-- re-point the same link to whichever ExecEnv ran last, so such configs keep the initial design:
-- links only at install. Failures only warn: mise would print an error raised here with a stack
-- trace and, since it caches only results, raise it again on every run.
-- Skills add nothing to the environment.
function PLUGIN:BackendExecEnv(ctx)
    if ctx.options.root == nil then
        return { env_vars = {} }
    end
    local tmp
    local ok, err = pcall(function()
        tmp = os.tmpname()
        local dirs = targets.resolve(ctx.options, os.getenv("MISE_SKILL_AGENTS"), os.getenv("HOME"))
        local selected = skills.select(skills.discover(ctx.install_path), ctx.options.skills)
        links.install(ctx.install_path, tmp, selected, dirs)
    end)
    if tmp then
        os.remove(tmp) -- os.tmpname creates the file, and the link is built there only sometimes
    end
    if not ok then
        log.warn("mise-skill: could not link " .. ctx.tool .. ": " .. tostring(err))
    end
    return { env_vars = {} }
end
