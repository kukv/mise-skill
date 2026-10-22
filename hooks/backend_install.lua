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
