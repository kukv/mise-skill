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
