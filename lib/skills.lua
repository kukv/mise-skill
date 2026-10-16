local file = require("file")
local log = require("log")

local M = {}

-- parse_name(text) -> the "name:" value of a SKILL.md front matter, or nil.
function M.parse_name(text)
    local front = text:match("^%-%-%-\r?\n(.-)\r?\n%-%-%-")
    if front == nil then
        return nil
    end
    for line in front:gmatch("[^\r\n]+") do
        local value = line:match("^name:%s*(.-)%s*$")
        if value ~= nil then
            value = (value:gsub("^[\"'](.*)[\"']$", "%1"))
            if value ~= "" then
                return value
            end
            return nil
        end
    end
    return nil
end

-- with_name(text, name) -> text with the "name:" value of its front matter replaced by name.
function M.with_name(text, name)
    local head, front, tail = text:match("^(%-%-%-\r?\n)(.-)(\r?\n%-%-%-.*)$")
    local replaced, count = ("\n" .. (front or "")):gsub("\nname:[^\r\n]*", "\nname: " .. name, 1)
    if count == 0 then
        error("mise-skill: no name in the front matter of the SKILL.md to rename")
    end
    return head .. replaced:sub(2) .. tail
end

local VALID_NAME = "^[%w][%w._-]*$"

-- discover(root) -> every skill under root as { name, dir }, where dir holds SKILL.md.
function M.discover(root)
    local found = {}
    for _, path in ipairs(file.glob(file.join_path(root, "**", "SKILL.md"))) do
        local name = M.parse_name(file.read(path))
        if name ~= nil and not name:match(VALID_NAME) then
            log.warn("mise-skill: ignored " .. path .. ": invalid skill name " .. name)
        elseif name ~= nil then
            table.insert(found, { name = name, dir = path:sub(1, #path - #"/SKILL.md") })
        end
    end
    if #found == 0 then
        error("mise-skill: no SKILL.md with a name was found in " .. root)
    end
    return found
end

-- select(found, wanted) -> the skills to link. wanted is the skills tool option: nil means
-- all of them, a string means one. Unknown and ambiguous names fail.
function M.select(found, wanted)
    local by_name, order = {}, {}
    for _, skill in ipairs(found) do
        if by_name[skill.name] == nil then
            by_name[skill.name] = {}
            table.insert(order, skill.name)
        end
        table.insert(by_name[skill.name], skill)
    end
    if type(wanted) == "string" then
        wanted = { wanted }
    end
    local names = wanted or order
    local selected = {}
    for _, name in ipairs(names) do
        local matches = by_name[name]
        if matches == nil then
            error("mise-skill: no skill named " .. name .. " (found: " .. table.concat(order, ", ") .. ")")
        elseif #matches > 1 then
            local dirs = {}
            for _, skill in ipairs(matches) do
                table.insert(dirs, skill.dir)
            end
            error("mise-skill: more than one skill is named " .. name .. ": " .. table.concat(dirs, ", "))
        end
        table.insert(selected, matches[1])
    end
    return selected
end

-- rename(selected, renames) -> selected with each skill named in renames (the rename tool
-- option, { old = "new" }) given its new name, in the link and in its SKILL.md, because the
-- agents name a skill by its front matter. Unknown, invalid and duplicate names fail.
function M.rename(selected, renames)
    if renames == nil then
        return selected
    end
    local by_name = {}
    for _, skill in ipairs(selected) do
        by_name[skill.name] = skill
    end
    for old, new in pairs(renames) do
        if type(old) ~= "string" or type(new) ~= "string" then
            error('mise-skill: rename must be a table of names, e.g. rename = { alpha = "my-alpha" }')
        elseif by_name[old] == nil then
            error("mise-skill: rename names " .. old .. ", which is not a selected skill")
        elseif not new:match(VALID_NAME) then
            error("mise-skill: invalid name in rename: " .. new)
        end
    end
    local out, seen = {}, {}
    for _, skill in ipairs(selected) do
        local name = renames[skill.name] or skill.name
        if seen[name] then
            error("mise-skill: more than one skill would be named " .. name .. " after rename")
        end
        seen[name] = true
        if name ~= skill.name then
            local path = file.join_path(skill.dir, "SKILL.md")
            local text = M.with_name(file.read(path), name) -- read before io.open truncates it
            local f = assert(io.open(path, "w"))
            f:write(text)
            f:close()
        end
        table.insert(out, { name = name, dir = skill.dir })
    end
    return out
end

return M
