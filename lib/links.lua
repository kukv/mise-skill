local file = require("file")
local json = require("json")
local log = require("log")

local M = {}

M.MARKER = ".mise-skill" -- in each linked skill dir; holds the install_path that owns it
M.RECORD = ".mise-skill.json" -- in install_path; the links this version placed, by base directory
M.LEGACY = "" -- the record's key for links recorded as a plain list, by mise-skill 0.1
M.TMP_LINK = ".mise-skill-link-" -- prefix of the temporary link that sync builds in install_path

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

-- place(src, dst, tmp): point dst at src. file.symlink fails when dst's parent is missing,
-- but file.move creates parents, so then the link is built at tmp and moved. If dst is on
-- another filesystem that move fails after creating the parent, and the link is built beside.
local function place(src, dst, tmp)
    if not file.exists(dirname(dst)) then
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

-- remove(dst, install_path): remove dst if it is a mise-skill link that still points at
-- install_path. After an upgrade an old version's links already point elsewhere.
local function remove(dst, install_path)
    local kind, owner = M.classify(dst)
    if kind == "ours" and owner == install_path then
        local ok, err = os.remove(dst)
        if not ok then
            log.warn("mise-skill: could not remove " .. dst .. ": " .. tostring(err))
        end
    end
end

-- read_record(install_path) -> { [base] = { dst, ... } }, or {} when it is missing or unreadable.
-- A plain list is the record of mise-skill 0.1; it is kept under M.LEGACY so uninstall removes it.
local function read_record(install_path)
    local record = file.join_path(install_path, M.RECORD)
    if not file.exists(record) then
        return {}
    end
    local ok, value = pcall(json.decode, file.read(record))
    if not ok or type(value) ~= "table" then
        return {}
    end
    if value[1] ~= nil then
        return { [M.LEGACY] = value }
    end
    return value
end

-- write_record(install_path, by_base): rename over the record so a concurrent read_record never
-- sees a partial file.
local function write_record(install_path, by_base)
    local record = file.join_path(install_path, M.RECORD)
    local tmp = record .. ".tmp" .. tostring(os.time()) .. tostring(math.random(1e9))
    write(tmp, json.encode(by_base))
    local ok, err = os.rename(tmp, record)
    if not ok then
        os.remove(tmp)
        error(err, 0)
    end
end

-- sync(install_path, base, selected, dirs): for the config whose base directory is base, mark
-- each selected skill as owned by install_path, link it into every dir, remove what this config
-- linked last time and no longer wants, and record the links under base. One version serves
-- every config that uses it, so the other bases are other configs and are left alone.
function M.sync(install_path, base, selected, dirs)
    -- A name of its own, since ExecEnv can run in two shells at once; discover skips it.
    local tmp = file.join_path(install_path, M.TMP_LINK .. tostring(os.time()) .. tostring(math.random(1e9)))
    local by_base = read_record(install_path)
    local placed, wanted = {}, {}
    for _, skill in ipairs(selected) do
        write(file.join_path(skill.dir, M.MARKER), install_path)
        for _, dir in ipairs(dirs) do
            local dst = file.join_path(dir, skill.name)
            wanted[dst] = true
            local kind, owner = M.classify(dst)
            if kind == "foreign" then
                log.warn("mise-skill: skipped " .. dst .. ": it exists and mise-skill did not create it")
            elseif kind == "ours" and dirname(owner) ~= dirname(install_path) then
                -- Another version of this tool is replaced (that is an upgrade); another tool is not.
                log.warn("mise-skill: skipped " .. dst .. ": another tool links it, installed at " .. owner)
            else
                local ok, err = pcall(place, skill.dir, dst, tmp)
                if ok then
                    table.insert(placed, dst)
                else
                    log.warn("mise-skill: could not link " .. dst .. ": " .. tostring(err))
                end
            end
        end
    end
    for _, dst in ipairs(by_base[base] or {}) do
        if not wanted[dst] then
            remove(dst, install_path)
        end
    end
    by_base[base] = placed
    write_record(install_path, by_base)
end

-- uninstall(install_path): remove the links this version recorded, for every base, that still
-- point at it. ctx.options is unreliable here (defaults only during prune), so use the record.
function M.uninstall(install_path)
    for _, dsts in pairs(read_record(install_path)) do
        for _, dst in ipairs(dsts) do
            remove(dst, install_path)
        end
    end
end

return M
