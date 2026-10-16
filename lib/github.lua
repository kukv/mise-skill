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

-- ref_for(repo, version) -> the git ref to download. "ref:<x>" is used as is; a version is
-- matched against the tags with or without a leading "v". A tag is returned as refs/tags/<tag>
-- so that a branch of the same name is never downloaded instead.
function M.ref_for(repo, version)
    if version:sub(1, 4) == "ref:" then
        return version:sub(5)
    end
    for _, tag in ipairs(M.tags(repo)) do
        if tag == version or tag == "v" .. version then
            return "refs/tags/" .. tag
        end
    end
    error("mise-skill: " .. repo .. " has no tag " .. version .. " or v" .. version)
end

-- tarball_url(repo, ref) -> the source tarball. No token: codeload.github.com rejects it.
function M.tarball_url(repo, ref)
    return "https://codeload.github.com/" .. repo .. "/tar.gz/" .. ref
end

return M
