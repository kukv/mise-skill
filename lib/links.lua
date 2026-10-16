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
