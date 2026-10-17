-- Build strings: "TFG1:" + base64 of
--   version(1) classID(1) kind(1) count(1) point... checksum(2)
-- Each point is a varint: the talent's spell id (kind 1, survives hotfixes that renumber nodes) or its node id (kind 2).
-- The points are in the order you take them.
local ADDON, TP = ...

local PREFIX = "TFG1:"
local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local INDEX = {}
for i = 1, #ALPHABET do
    INDEX[ALPHABET:sub(i, i)] = i - 1
end

local function Base64Encode(bytes)
    local out = {}
    for i = 1, #bytes, 3 do
        local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
        if b then
            out[#out + 1] = ALPHABET:sub(c3 + 1, c3 + 1)
        end
        if c then
            out[#out + 1] = ALPHABET:sub(c4 + 1, c4 + 1)
        end
    end
    return table.concat(out)
end

local function Base64Decode(text)
    local bytes = {}
    for i = 1, #text, 4 do
        local chunk = text:sub(i, i + 3)
        local size = #chunk
        if size == 1 then
            return nil
        end
        local v = {}
        for k = 1, size do
            local value = INDEX[chunk:sub(k, k)]
            if value == nil then
                return nil
            end
            v[k] = value
        end
        local n = v[1] * 262144 + v[2] * 4096 + (v[3] or 0) * 64 + (v[4] or 0)
        bytes[#bytes + 1] = math.floor(n / 65536) % 256
        if size >= 3 then
            bytes[#bytes + 1] = math.floor(n / 256) % 256
        end
        if size == 4 then
            bytes[#bytes + 1] = n % 256
        end
    end
    return bytes
end

local function PushVarint(bytes, value)
    while value >= 128 do
        bytes[#bytes + 1] = (value % 128) + 128
        value = math.floor(value / 128)
    end
    bytes[#bytes + 1] = value
end

-- Returns the value and the next position, or nil when the bytes run out.
local function ReadVarint(bytes, position)
    local value, multiplier = 0, 1
    while true do
        local byte = bytes[position]
        if not byte then
            return nil
        end
        position = position + 1
        value = value + (byte % 128) * multiplier
        if byte < 128 then
            return value, position
        end
        multiplier = multiplier * 128
        if multiplier > 268435456 then
            return nil
        end
    end
end

local function Checksum(bytes, count)
    local sum = 0
    for i = 1, count do
        sum = (sum * 31 + bytes[i]) % 65521
    end
    return sum
end

local function PlayerClassID()
    local classID = select(3, UnitClass("player"))
    if (issecretvalue and issecretvalue(classID)) or type(classID) ~= "number" then
        return 0
    end
    return classID
end

-- classID: the class the tree belongs to. Defaults to yours.
function TP:Export(plan, meta, classID)
    if not plan or #plan.order == 0 then
        return nil, "empty"
    end

    local useSpells = true
    for _, entry in ipairs(plan.order) do
        local node = meta.nodes[entry.n]
        if not (node and node.spell) then
            useSpells = false
            break
        end
    end

    local bytes = { 1, classID or PlayerClassID(), useSpells and 1 or 2, #plan.order }
    for _, entry in ipairs(plan.order) do
        PushVarint(bytes, useSpells and meta.nodes[entry.n].spell or entry.n)
    end

    local sum = Checksum(bytes, #bytes)
    bytes[#bytes + 1] = math.floor(sum / 256)
    bytes[#bytes + 1] = sum % 256
    return PREFIX .. Base64Encode(bytes)
end

-- Returns the order, or nil plus an error key (and the build's class id for "class").
-- classID: the class whose tree `meta` describes. Defaults to yours.
function TP:Decode(text, meta, wantedClassID)
    text = tostring(text or ""):gsub("%s+", "")
    if text == "" then
        return nil, "empty"
    end

    local body = text:match("^" .. PREFIX .. "(.+)$")
    local bytes = body and Base64Decode(body)
    if not bytes or #bytes < 6 then
        return nil, "format"
    end

    local total = #bytes
    local sum = Checksum(bytes, total - 2)
    if bytes[total - 1] ~= math.floor(sum / 256) or bytes[total] ~= sum % 256 then
        return nil, "checksum"
    end
    if bytes[1] ~= 1 then
        return nil, "version"
    end

    local classID, kind, count = bytes[2], bytes[3], bytes[4]
    local mine = wantedClassID or PlayerClassID()
    if mine ~= 0 and classID ~= 0 and classID ~= mine then
        return nil, "class", classID
    end
    if (kind ~= 1 and kind ~= 2) or count == 0 or count > TP.POINT_CAP then
        return nil, "format"
    end

    local order = {}
    local position = 5
    for _ = 1, count do
        local value
        value, position = ReadVarint(bytes, position)
        if not value or position > total - 1 then
            return nil, "format"
        end
        local nodeID = kind == 1 and meta.bySpell[value] or (kind == 2 and meta.nodes[value] and value) or nil
        if not nodeID then
            return nil, "invalid"
        end
        order[#order + 1] = { n = nodeID, s = meta.nodes[nodeID].spell }
    end
    if position ~= total - 1 then
        return nil, "format"
    end

    if not self:ValidateOrder(meta, order) then
        return nil, "invalid"
    end
    return order
end
