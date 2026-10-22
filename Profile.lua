-- Settings profile: everything Talents Forge saves (mode, toggles, where the chip, bar and browser window sit, and every
-- plan) as one string, "TFP1:" + base64 of
--   version(1) value... checksum(2)
-- This is separate from the build strings in Codec.lua ("TFG1:"), which carry one plan. A profile is meant for moving your
-- whole setup to another character or another install.
-- Values are written in a small binary form: false, true, unsigned and negative integers, decimals, strings, and tables
-- (a count, then key and value for each). Reading never runs anything: it only builds plain tables, and every field is
-- checked before it reaches the saved variables.
local ADDON, TP = ...
local L = TP.L

local PREFIX = "TFP1:"
local VERSION = 1

local T_FALSE, T_TRUE, T_UINT, T_NINT, T_STRING, T_TABLE, T_DECIMAL = 1, 2, 3, 4, 5, 6, 7
local MAX_DEPTH, MAX_VALUES, MAX_STRING = 6, 40000, 400
local MAX_OFFSET = 4000 -- how far from the centre a saved position may be

-- The keys of the saved variables a profile carries. A key the game saves that is not listed here would be left out of
-- exports and ignored by imports, so the tests compare this list with what InitDB creates.
TP.PROFILE_KEYS = { "mode", "focus", "animations", "pos", "plans", "active" }

TP.REASONS.pformat = L["That doesn't look like a Talents Forge profile string."]
TP.REASONS.pbuild = L["That is a build string, not a profile. Use Share build from the menu."]
TP.REASONS.pchecksum = L["That string is damaged. Copy it again."]
TP.REASONS.pversion = L["That profile is from a newer version of Talents Forge."]
TP.REASONS.pdamaged = L["That profile can't be read."]
TP.REASONS.pempty = L["Paste a profile string first."]

local function Codec()
    return TP.Codec
end

------------------------------------------------------------------------------------------------------------------------
-- Writing and reading values
------------------------------------------------------------------------------------------------------------------------

local function PushString(bytes, text)
    Codec().PushVarint(bytes, #text)
    for i = 1, #text do
        bytes[#bytes + 1] = text:byte(i)
    end
end

local function SortedKeys(tbl)
    local keys = {}
    for key in pairs(tbl) do
        local kind = type(key)
        if kind == "number" or kind == "string" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then
            return ta == "number"
        end
        return a < b
    end)
    return keys
end

local function Write(bytes, value, depth)
    local kind = type(value)
    if kind == "boolean" then
        bytes[#bytes + 1] = value and T_TRUE or T_FALSE
    elseif kind == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            error("number")
        end
        if value == math.floor(value) and value > -2147483648 and value < 2147483648 then
            bytes[#bytes + 1] = value >= 0 and T_UINT or T_NINT
            Codec().PushVarint(bytes, math.abs(value))
        else
            bytes[#bytes + 1] = T_DECIMAL
            PushString(bytes, string.format("%.10g", value))
        end
    elseif kind == "string" then
        bytes[#bytes + 1] = T_STRING
        PushString(bytes, value)
    elseif kind == "table" then
        if depth > MAX_DEPTH then
            error("depth")
        end
        local keys = SortedKeys(value)
        bytes[#bytes + 1] = T_TABLE
        Codec().PushVarint(bytes, #keys)
        for _, key in ipairs(keys) do
            Write(bytes, key, depth + 1)
            Write(bytes, value[key], depth + 1)
        end
    else
        error("type")
    end
end

local function ReadString(bytes, position)
    local length, after = Codec().ReadVarint(bytes, position)
    if not length or length > MAX_STRING or after + length - 1 > #bytes then
        error("string")
    end
    local chars = {}
    for i = 0, length - 1 do
        chars[#chars + 1] = string.char(bytes[after + i])
    end
    return table.concat(chars), after + length
end

local function Read(bytes, position, depth, budget)
    budget.count = budget.count + 1
    if budget.count > MAX_VALUES or depth > MAX_DEPTH + 1 then
        error("size")
    end
    local tag = bytes[position]
    if not tag then
        error("short")
    end
    position = position + 1
    if tag == T_FALSE then
        return false, position
    elseif tag == T_TRUE then
        return true, position
    elseif tag == T_UINT or tag == T_NINT then
        local value, after = Codec().ReadVarint(bytes, position)
        if not value then
            error("short")
        end
        return tag == T_UINT and value or -value, after
    elseif tag == T_DECIMAL then
        local text, after = ReadString(bytes, position)
        local value = tonumber(text)
        if not value or value ~= value or value == math.huge or value == -math.huge then
            error("number")
        end
        return value, after
    elseif tag == T_STRING then
        return ReadString(bytes, position)
    elseif tag == T_TABLE then
        local count, after = Codec().ReadVarint(bytes, position)
        if not count or count > #bytes then
            error("count")
        end
        position = after
        local result = {}
        for _ = 1, count do
            local key, value
            key, position = Read(bytes, position, depth + 1, budget)
            if type(key) ~= "number" and type(key) ~= "string" then
                error("key")
            end
            value, position = Read(bytes, position, depth + 1, budget)
            result[key] = value
        end
        return result, position
    end
    error("tag")
end

------------------------------------------------------------------------------------------------------------------------
-- Export
------------------------------------------------------------------------------------------------------------------------

-- Returns the string and the number of plans in it, or nil and a reason.
function TP:ExportProfile()
    local source = {}
    for _, key in ipairs(TP.PROFILE_KEYS) do
        source[key] = self.db[key]
    end

    local bytes = { VERSION }
    local ok = pcall(Write, bytes, source, 1)
    if not ok then
        return nil, "pdamaged"
    end
    local sum = Codec().Checksum(bytes, #bytes)
    bytes[#bytes + 1] = math.floor(sum / 256) % 256
    bytes[#bytes + 1] = sum % 256

    local count = 0
    for _, plans in pairs(self.db.plans) do
        count = count + #plans
    end
    return PREFIX .. Codec().Base64Encode(bytes), count
end

------------------------------------------------------------------------------------------------------------------------
-- Import
------------------------------------------------------------------------------------------------------------------------

local function Integer(value)
    return math.floor(value + 0.5)
end

-- Builds a clean profile from whatever was decoded: defaults for anything missing, nothing unknown, every number checked.
local function Sanitize(raw)
    local profile = { mode = "guide", focus = false, animations = true, pos = {}, plans = {}, active = {} }
    if type(raw) ~= "table" then
        return profile
    end

    if raw.mode == "off" or raw.mode == "guide" or raw.mode == "edit" then
        profile.mode = raw.mode
    end
    if type(raw.focus) == "boolean" then
        profile.focus = raw.focus
    end
    if type(raw.animations) == "boolean" then
        profile.animations = raw.animations
    end

    if type(raw.pos) == "table" then
        for key, offset in pairs(raw.pos) do
            if type(key) == "string" and #key <= 24 and type(offset) == "table"
                and type(offset[1]) == "number" and type(offset[2]) == "number"
                and math.abs(offset[1]) <= MAX_OFFSET and math.abs(offset[2]) <= MAX_OFFSET then
                profile.pos[key] = { Integer(offset[1]), Integer(offset[2]) }
            end
        end
    end

    if type(raw.plans) == "table" then
        for tree, list in pairs(raw.plans) do
            if type(tree) == "number" and TP:ClassByTree(tree) and type(list) == "table" then
                local plans = {}
                for index = 1, math.min(#list, 60) do
                    local plan = list[index]
                    if type(plan) == "table" and type(plan.order) == "table" then
                        local order = {}
                        for k = 1, math.min(#plan.order, TP.POINT_CAP) do
                            local entry = plan.order[k]
                            if type(entry) == "table" and type(entry.n) == "number" and entry.n > 0 then
                                order[#order + 1] = {
                                    n = Integer(entry.n),
                                    s = type(entry.s) == "number" and entry.s > 0 and Integer(entry.s) or nil,
                                }
                            end
                        end
                        local name = type(plan.name) == "string" and TP.Trim(plan.name):sub(1, 28) or ""
                        plans[#plans + 1] = {
                            name = name ~= "" and name or L["Plan"],
                            order = order,
                            updated = type(plan.updated) == "number" and Integer(plan.updated) or 0,
                        }
                    end
                end
                if #plans > 0 then
                    profile.plans[tree] = plans
                end
            end
        end
    end

    if type(raw.active) == "table" then
        for tree, name in pairs(raw.active) do
            if type(tree) == "number" and TP:ClassByTree(tree) and type(name) == "string" then
                profile.active[tree] = TP.Trim(name):sub(1, 28)
            end
        end
    end
    return profile
end

-- Returns the checked profile, or nil and a reason. Changes nothing.
function TP:DecodeProfile(text)
    text = tostring(text or ""):gsub("%s", "")
    if text == "" then
        return nil, "pempty"
    end
    if text:sub(1, 5) == "TFG1:" then
        return nil, "pbuild"
    end
    if text:sub(1, #PREFIX) ~= PREFIX then
        return nil, "pformat"
    end
    local bytes = Codec().Base64Decode(text:sub(#PREFIX + 1))
    if not bytes or #bytes < 4 then
        return nil, "pformat"
    end
    local body = #bytes - 2
    local sum = Codec().Checksum(bytes, body)
    if bytes[body + 1] ~= math.floor(sum / 256) % 256 or bytes[body + 2] ~= sum % 256 then
        return nil, "pchecksum"
    end
    if bytes[1] > VERSION then
        return nil, "pversion"
    end

    local payload = {}
    for i = 1, body do
        payload[i] = bytes[i]
    end
    local ok, raw, position = pcall(Read, payload, 2, 1, { count = 0 })
    if not ok or position ~= body + 1 or type(raw) ~= "table" then
        return nil, "pdamaged"
    end
    return Sanitize(raw)
end

local function SamePlan(a, b)
    if a.name ~= b.name or #a.order ~= #b.order then
        return false
    end
    for index, entry in ipairs(a.order) do
        if entry.n ~= b.order[index].n then
            return false
        end
    end
    return true
end

-- Settings and positions are replaced. Plans are added next to yours, and a plan you already have is not added twice, so
-- importing never deletes anything. Returns { added = number, skipped = number }, or nil and a reason.
function TP:ImportProfile(text)
    local profile, err = self:DecodeProfile(text)
    if not profile then
        return nil, err
    end

    local db = self.db
    db.mode, db.focus, db.animations, db.pos = profile.mode, profile.focus, profile.animations, profile.pos

    local added, skipped = 0, 0
    for tree, plans in pairs(profile.plans) do
        local mine = self:Plans(tree)
        local hadPlans = #mine > 0
        local activeName
        for _, plan in ipairs(plans) do
            local duplicate
            for _, existing in ipairs(mine) do
                if SamePlan(existing, plan) then
                    duplicate = true
                    break
                end
            end
            if duplicate then
                skipped = skipped + 1
            else
                local wanted = plan.name
                plan.name = self:UniqueName(tree, plan.name)
                mine[#mine + 1] = plan
                added = added + 1
                if wanted == profile.active[tree] then
                    activeName = plan.name
                end
            end
        end
        if not hadPlans and activeName then
            db.active[tree] = activeName
        end
    end

    self:InitDB() -- settles anything that doesn't fit, and keeps the saved variables the same table
    self.view = nil
    if self.UI and self.UI.ProfileApplied then
        self.UI:ProfileApplied()
    end
    return { added = added, skipped = skipped }
end
