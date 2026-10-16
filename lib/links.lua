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

local function dirname(path)
    return (path:match("^(.*)/[^/]*$"))
end

-- link_beside(src, dst): build the link next to dst and rename it over dst. The rename replaces
-- an existing link in one step and, unlike a rename from tmpdir, never crosses filesystems.
local function link_beside(src, dst)
    local tmp = dst .. ".mise-skill-tmp"
    os.remove(tmp) -- a stale link from an earlier failed run would make symlink fail
    file.symlink(src, tmp)
    local ok, err = pcall(file.move, tmp, dst)
    if not ok then
        os.remove(tmp) -- an agent would read a leftover link as one more skill
        error(err, 0)
    end
end

-- place(src, dst, tmpdir): point dst at src. file.symlink fails when dst's parent is missing,
-- but file.move creates parents, so then the link is built in tmpdir and moved. If dst is on
-- another filesystem that move fails after creating the parent, and the link is built beside.
local function place(src, dst, tmpdir)
    if not file.exists(dirname(dst)) then
        local tmp = file.join_path(tmpdir, "mise-skill-link")
        os.remove(tmp)
        file.symlink(src, tmp)
        local ok, err = pcall(file.move, tmp, dst)
        os.remove(tmp)
        if ok then
            return
        elseif not file.exists(dirname(dst)) then
            error(err, 0)
        end
    end
    link_beside(src, dst)
end

-- install(install_path, tmpdir, selected, dirs): mark each selected skill as owned by
-- install_path, link it into every dir, and record the links that were placed.
function M.install(install_path, tmpdir, selected, dirs)
    local placed = {}
    for _, skill in ipairs(selected) do
        write(file.join_path(skill.dir, M.MARKER), install_path)
        for _, dir in ipairs(dirs) do
            local dst = file.join_path(dir, skill.name)
            local kind, owner = M.classify(dst)
            if kind == "foreign" then
                log.warn("mise-skill: skipped " .. dst .. ": it exists and mise-skill did not create it")
            elseif kind == "ours" and dirname(owner) ~= dirname(install_path) then
                -- Another version of this tool is replaced (that is an upgrade); another tool is not.
                log.warn("mise-skill: skipped " .. dst .. ": another tool links it, installed at " .. owner)
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

-- uninstall(install_path): remove the links this version recorded that still point at it.
-- ctx.options is unreliable here (defaults only during prune), so use the record.
-- After an upgrade the old version is removed later; its links already point elsewhere.
function M.uninstall(install_path)
    local record = file.join_path(install_path, M.RECORD)
    if not file.exists(record) then
        return
    end
    local ok, dsts = pcall(json.decode, file.read(record))
    if not ok then
        log.warn("mise-skill: could not read " .. record .. ": " .. tostring(dsts))
        return
    end
    for _, dst in ipairs(dsts) do
        local kind, owner = M.classify(dst)
        if kind == "ours" and owner == install_path then
            local ok, err = os.remove(dst)
            if not ok then
                log.warn("mise-skill: could not remove " .. dst .. ": " .. tostring(err))
            end
        end
    end
end

return M
