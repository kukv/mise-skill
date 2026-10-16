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
