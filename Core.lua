-- Talents Forge core: saved plans, the talent tree's rules, and "what is my next talent".
-- A plan is an ordered list of points: plan.order[k] = { n = nodeID, s = spellID } is the talent you take at level 9 + k.
-- Plans are virtual. Nothing here ever spends a real talent point.
local ADDON, TP = ...
_G.TalentsForge = TP

local POINT_CAP = 51
local FIRST_LEVEL = 10 -- the first talent point is spent at level 10
TP.POINT_CAP = POINT_CAP
TP.FIRST_LEVEL = FIRST_LEVEL

local EDGE_TYPES = Enum and Enum.TraitEdgeType
local EDGE_VISUAL_ONLY = EDGE_TYPES and EDGE_TYPES.VisualOnly or 0
local EDGE_SUFFICIENT = EDGE_TYPES and EDGE_TYPES.SufficientForAvailability or 2
local EDGE_EXCLUSIVE = EDGE_TYPES and EDGE_TYPES.MutuallyExclusive or 4

TP.REASONS = {
    max = "That talent is already at max rank in this plan.",
    cap = "The plan already uses all 51 points.",
    prereq = "Plan the talent that leads to it first.",
    gate = "Plan more points in this tree first.",
    level = "That talent isn't available by level 60.",
    unknown = "That talent isn't in this tree.",
    none = "There's no planned point to remove there.",
    noplan = "Create a plan first.",
    dependents = "Other planned talents depend on this one. Remove those first.",
    format = "That doesn't look like a Talents Forge build string.",
    checksum = "That string is damaged. Copy it again.",
    version = "That string is from a newer version of Talents Forge.",
    invalid = "That build doesn't fit this talent tree.",
    empty = "Nothing to export yet. Plan at least one talent.",
}

function TP:ErrorText(err, extra)
    if err == "class" then
        local name = extra and GetClassInfo and GetClassInfo(extra)
        return "That build is for " .. (name or "another class") .. "."
    end
    return TP.REASONS[err] or tostring(err)
end

function TP:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff40c7b3Talents Forge:|r " .. tostring(message))
end

function TP:Error(message)
    if UIErrorsFrame then
        UIErrorsFrame:AddMessage(tostring(message), 1, 0.3, 0.3, 1)
    end
end

function TP:LevelOf(pointIndex)
    return FIRST_LEVEL - 1 + pointIndex
end

------------------------------------------------------------------------------------------------------------------------
-- Saved variables
------------------------------------------------------------------------------------------------------------------------

function TP:InitDB()
    if type(TalentsForgeDB) ~= "table" then
        TalentsForgeDB = {}
    end
    local db = TalentsForgeDB
    db.plans = type(db.plans) == "table" and db.plans or {}   -- [treeID] = { plan, ... }
    db.active = type(db.active) == "table" and db.active or {} -- [treeID] = plan name
    db.probe, db.artFit = nil, nil -- left behind by earlier versions
    db.pos = type(db.pos) == "table" and db.pos or {}         -- moved frames, as offsets from the talent window's centre
    if db.mode ~= "off" and db.mode ~= "guide" and db.mode ~= "edit" then
        db.mode = "guide"
    end
    self.db = db
end

local function Trim(value)
    value = tostring(value or "")
    value = value:gsub("%c", "")
    value = value:gsub("^%s+", "")
    value = value:gsub("%s+$", "")
    return value
end
TP.Trim = Trim

------------------------------------------------------------------------------------------------------------------------
-- The talent tree: what each node costs, what it needs, which spell it is
------------------------------------------------------------------------------------------------------------------------

-- Every class has one tree id. They don't change between builds, and the game answers for all of them through your own
-- talent config, so other classes can be browsed with the same code as your own.
TP.CLASSES = {
    { token = "WARRIOR", id = 1, tree = 1117, specs = { "Arms", "Fury", "Protection" },
      icons = { "ability_rogue_eviscerate", "ability_warrior_innerrage", "inv_shield_06" } },
    { token = "PALADIN", id = 2, tree = 1100, specs = { "Holy", "Protection", "Retribution" },
      icons = { "spell_holy_holybolt", "spell_holy_devotionaura", "spell_holy_auraoflight" } },
    { token = "HUNTER", id = 3, tree = 1091, specs = { "Beast Mastery", "Marksmanship", "Survival" },
      icons = { "ability_hunter_beasttaming", "ability_marksmanship", "ability_hunter_swiftstrike" } },
    { token = "ROGUE", id = 4, tree = 1111, specs = { "Assassination", "Combat", "Subtlety" },
      icons = { "ability_rogue_eviscerate", "ability_backstab", "ability_stealth" } },
    { token = "PRIEST", id = 5, tree = 1114, specs = { "Discipline", "Holy", "Shadow" },
      icons = { "spell_holy_wordfortitude", "spell_holy_guardianspirit", "spell_shadow_shadowwordpain" } },
    { token = "SHAMAN", id = 7, tree = 1082, specs = { "Elemental", "Enhancement", "Restoration" },
      icons = { "spell_nature_lightning", "spell_nature_lightningshield", "spell_nature_magicimmunity" } },
    { token = "MAGE", id = 8, tree = 1112, specs = { "Arcane", "Fire", "Frost" },
      icons = { "spell_holy_magicalsentry", "spell_fire_firebolt02", "spell_frost_frostbolt02" } },
    { token = "WARLOCK", id = 9, tree = 1116, specs = { "Affliction", "Demonology", "Destruction" },
      icons = { "spell_shadow_deathcoil", "spell_shadow_metamorphosis", "spell_shadow_rainoffire" } },
    { token = "DRUID", id = 11, tree = 1089, specs = { "Balance", "Feral Combat", "Restoration" },
      icons = { "spell_nature_starfall", "ability_racial_bearform", "spell_nature_healingtouch" } },
}

function TP:ClassByTree(treeID)
    for _, entry in ipairs(self.CLASSES) do
        if entry.tree == treeID then
            return entry
        end
    end
end

function TP:ClassByID(classID)
    for _, entry in ipairs(self.CLASSES) do
        if entry.id == classID then
            return entry
        end
    end
end

function TP:ClassName(entry)
    local name = GetClassInfo and GetClassInfo(entry.id)
    return name or (entry.token:sub(1, 1) .. entry.token:sub(2):lower())
end

-- What the talent window is showing: "edit" and "guide" are your choice, but another class's tree is only ever planned.
function TP:Mode()
    return self.browse and "edit" or self.db.mode
end

function TP:GetTalentFrame()
    if PlayerSpellsFrame and PlayerSpellsFrame.TalentsFrame then
        return PlayerSpellsFrame.TalentsFrame
    end
    return ClassTalentFrame
end

-- Returns talentFrame, configID, treeID, or nil while the tree isn't ready.
function TP:GetContext()
    local talentFrame = self:GetTalentFrame()
    if not talentFrame or not C_Traits then
        return nil
    end

    local configID = talentFrame.GetConfigID and talentFrame:GetConfigID()
    if not configID and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        configID = C_ClassTalents.GetActiveConfigID()
    end

    local treeID = talentFrame.GetTalentTreeID and talentFrame:GetTalentTreeID()
    if not treeID and configID and C_Traits.GetConfigInfo then
        local configInfo = C_Traits.GetConfigInfo(configID)
        treeID = configInfo and configInfo.treeIDs and configInfo.treeIDs[1]
    end

    if not configID or not treeID then
        return nil
    end

    self.ownTreeID = treeID
    if self.browse and self.UI and self.UI.viewer then
        return self.UI.viewer, configID, self.browse
    end
    return talentFrame, configID, treeID
end

-- Some trees carry nodes parked far outside the grid (not drawn by the game's own window). They would stretch the layout
-- and split the trees wrongly, so anything well beyond where nearly all of the talents sit is left out.
local function Percentile(sorted, fraction)
    local index = math.floor(fraction * (#sorted - 1) + 1.5)
    return sorted[math.max(1, math.min(#sorted, index))]
end

local function DropStrays(meta)
    local xs, ys = {}, {}
    for _, node in pairs(meta.nodes) do
        xs[#xs + 1] = node.x
        ys[#ys + 1] = node.y
    end
    if #xs < 12 then
        return
    end
    table.sort(xs)
    table.sort(ys)
    local x10, x90 = Percentile(xs, 0.1), Percentile(xs, 0.9)
    local y10, y90 = Percentile(ys, 0.1), Percentile(ys, 0.9)
    local rangeX, rangeY = math.max(x90 - x10, 1), math.max(y90 - y10, 1)
    for nodeID, node in pairs(meta.nodes) do
        if node.x < x10 - rangeX or node.x > x90 + rangeX or node.y < y10 - rangeY or node.y > y90 + rangeY then
            meta.nodes[nodeID] = nil
            meta.count = meta.count - 1
        end
    end

    -- A talent sitting alone, several times further from its nearest neighbour than talents usually are, is parked too.
    local list = {}
    for _, node in pairs(meta.nodes) do
        list[#list + 1] = node
    end
    local nearest, distances = {}, {}
    for i = 1, #list do
        local best = math.huge
        for j = 1, #list do
            if i ~= j then
                local dx, dy = list[i].x - list[j].x, list[i].y - list[j].y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance < best then
                    best = distance
                end
            end
        end
        nearest[i] = best
        if best > 0.5 and best < math.huge then
            distances[#distances + 1] = best
        end
    end
    if #distances < 12 then
        return
    end
    table.sort(distances)
    local typical = distances[math.floor(#distances / 2) + 1]
    for i, node in ipairs(list) do
        if nearest[i] > typical * 4 then
            meta.nodes[node.id] = nil
            meta.count = meta.count - 1
        end
    end
end

-- Which of the class's three trees each talent is in, left to right the way the window draws them.
-- Your own class says so through the currency each talent spends. For other classes the game may not report costs at all,
-- so the three trees are told apart by the wide gaps between them, and costs and gates are rebuilt from what is known.
local function AssignGroups(meta)
    local nodes = meta.nodes

    local minX = {}
    for _, node in pairs(nodes) do
        local currency = node.costs[1] and node.costs[1].id
        if currency then
            minX[currency] = math.min(minX[currency] or node.x, node.x)
        end
    end
    local currencies = {}
    for currency in pairs(minX) do
        currencies[#currencies + 1] = currency
    end
    table.sort(currencies, function(a, b)
        if minX[a] ~= minX[b] then
            return minX[a] < minX[b]
        end
        return a < b
    end)

    if #currencies >= 2 then
        local index = {}
        for i, currency in ipairs(currencies) do
            index[currency] = i
        end
        meta.groupCount = #currencies
        meta.groups = currencies
        local centre, count = {}, {}
        for _, node in pairs(nodes) do
            local currency = node.costs[1] and node.costs[1].id
            node.group = currency and index[currency] or nil
            if node.group then
                centre[node.group] = (centre[node.group] or 0) + node.x
                count[node.group] = (count[node.group] or 0) + 1
            end
        end
        for _, node in pairs(nodes) do -- a talent that costs nothing sits with the nearest tree
            if not node.group then
                local best, bestDistance = 1, math.huge
                for i = 1, #currencies do
                    local distance = math.abs(node.x - (centre[i] or 0) / math.max(count[i] or 1, 1))
                    if distance < bestDistance then
                        best, bestDistance = i, distance
                    end
                end
                node.group = best
            end
        end
        return
    end

    -- No costs: cut the tree at its widest gaps.
    local xs, seen = {}, {}
    for _, node in pairs(nodes) do
        if not seen[node.x] then
            seen[node.x] = true
            xs[#xs + 1] = node.x
        end
    end
    table.sort(xs)
    local gaps = {}
    for i = 2, #xs do
        gaps[#gaps + 1] = { size = xs[i] - xs[i - 1], at = (xs[i] + xs[i - 1]) / 2 }
    end
    table.sort(gaps, function(a, b) return a.size > b.size end)
    local cuts = {}
    for i = 1, math.min(2, #gaps) do
        cuts[#cuts + 1] = gaps[i].at
    end
    table.sort(cuts)

    meta.groupCount = #cuts + 1
    for _, node in pairs(nodes) do
        local group = 1
        for _, cut in ipairs(cuts) do
            if node.x > cut then
                group = group + 1
            end
        end
        node.group = group
    end

    -- The currency each tree spends is the one its talents' gates ask for.
    local votes = {}
    local hasGate = false
    for _, node in pairs(nodes) do
        for _, condition in ipairs(node.conds) do
            if condition.currency then
                votes[node.group] = votes[node.group] or {}
                votes[node.group][condition.currency] = (votes[node.group][condition.currency] or 0) + 1
            end
            if condition.spent and condition.spent > 0 then
                hasGate = true
            end
        end
    end
    local groupCurrency = {}
    for group = 1, meta.groupCount do
        local best, bestVotes = -group, 0 -- a made-up id when nothing says otherwise
        for currency, number in pairs(votes[group] or {}) do
            if number > bestVotes then
                best, bestVotes = currency, number
            end
        end
        groupCurrency[group] = best
    end
    meta.groups = groupCurrency

    for _, node in pairs(nodes) do
        if #node.costs == 0 then
            node.costs[1] = { id = groupCurrency[node.group], amount = 1 }
        end
    end

    -- Last resort, if the game gave no gates either: the classic rule of five points per row.
    if not hasGate then
        local rows, seenY = {}, {}
        for _, node in pairs(nodes) do
            if not seenY[node.y] then
                seenY[node.y] = true
                rows[#rows + 1] = node.y
            end
        end
        table.sort(rows)
        local rowOf = {}
        for i, y in ipairs(rows) do
            rowOf[y] = i - 1
        end
        for _, node in pairs(nodes) do
            local row = rowOf[node.y]
            if row > 0 then
                node.conds[#node.conds + 1] = { currency = groupCurrency[node.group], spent = 5 * row }
            end
        end
    end
end

local function BuildMeta(configID, treeID)
    local meta = { configID = configID, treeID = treeID, nodes = {}, bySpell = {}, count = 0 }

    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.ID and info.ID ~= 0 and info.isVisible ~= false then
            local node = {
                id = nodeID,
                max = info.maxRanks or 1,
                x = info.posX or 0,
                y = info.posY or 0,
                costs = {},
                conds = {},
                incoming = {},
                out = {},
            }

            local entryID = info.entryIDs and info.entryIDs[1]
            node.entry = entryID
            if entryID then
                local entry = C_Traits.GetEntryInfo(configID, entryID)
                local definition = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                node.spell = definition and (definition.spellID or definition.overriddenSpellID)
            end

            if C_Traits.GetNodeCost then
                for _, cost in ipairs(C_Traits.GetNodeCost(configID, nodeID) or {}) do
                    node.costs[#node.costs + 1] = { id = cost.ID, amount = cost.amount or 1 }
                end
            end
            if C_Traits.GetConditionInfo then
                for _, conditionID in ipairs(info.conditionIDs or {}) do
                    local condition = C_Traits.GetConditionInfo(configID, conditionID)
                    if condition then
                        node.conds[#node.conds + 1] = {
                            level = condition.playerLevel,
                            currency = condition.traitCurrencyID,
                            spent = condition.spentAmountRequired,
                        }
                    end
                end
            end

            meta.nodes[nodeID] = node
            meta.count = meta.count + 1
        end
    end

    DropStrays(meta)
    for nodeID, node in pairs(meta.nodes) do
        if node.spell and not meta.bySpell[node.spell] then
            meta.bySpell[node.spell] = nodeID
        end
    end

    for nodeID, node in pairs(meta.nodes) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        for _, edge in ipairs(info and info.visibleEdges or {}) do
            local target = meta.nodes[edge.targetNode]
            if target and edge.type ~= EDGE_EXCLUSIVE then
                node.out[#node.out + 1] = edge.targetNode -- drawn as a line in the class browser
                if edge.type ~= EDGE_VISUAL_ONLY then
                    target.incoming[#target.incoming + 1] = { src = nodeID, type = edge.type }
                end
            end
        end
    end

    AssignGroups(meta)
    return meta
end

function TP:GetMeta(configID, treeID)
    local meta = self.meta
    if meta and meta.configID == configID and meta.treeID == treeID then
        return meta
    end

    local ok, result = pcall(BuildMeta, configID, treeID)
    if not ok then
        if not self.warnedMeta then
            self.warnedMeta = true
            self:Print("Couldn't read the talent tree: " .. tostring(result))
        end
        return { configID = configID, treeID = treeID, nodes = {}, bySpell = {}, groups = {}, count = 0 }
    end
    self.meta = result
    return result
end

function TP:ForgetMeta()
    self.meta = nil
end

function TP:NodeName(meta, nodeID)
    local node = meta and meta.nodes[nodeID]
    local spell = node and node.spell
    if spell then
        local name
        if C_Spell and C_Spell.GetSpellName then
            name = C_Spell.GetSpellName(spell)
        elseif C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(spell)
            name = info and info.name
        end
        if name then
            return name
        end
    end
    return "talent"
end

-- Points spent per tree, left to right. Falls back to a single total when the trees can't be told apart.
function TP:Split(meta, order, count)
    count = math.min(count or #order, #order)
    local trees = meta.groupCount or 0
    if trees < 2 then
        return { count }
    end

    local split = {}
    for i = 1, trees do
        split[i] = 0
    end
    for k = 1, count do
        local node = meta.nodes[order[k].n]
        local group = node and node.group
        if group then
            split[group] = split[group] + 1
        end
    end
    return split
end

------------------------------------------------------------------------------------------------------------------------
-- Rules: can this ordered list of points be taken?
------------------------------------------------------------------------------------------------------------------------

-- Points are counted per tree: a gate that asks for 20 points means 20 in its own tree, not 20 anywhere in the class.
-- spent[tree][currency] = points spent so far.
local function Spend(spent, node)
    local key = node.group or 0
    local pool = spent[key]
    if not pool then
        pool = {}
        spent[key] = pool
    end
    for _, cost in ipairs(node.costs) do
        pool[cost.id] = (pool[cost.id] or 0) + cost.amount
    end
end

local function PrerequisitesMet(meta, node, ranks, spent)
    local sufficientEdges, sufficientMet = 0, false
    for _, edge in ipairs(node.incoming) do
        local source = meta.nodes[edge.src]
        local active = source and (ranks[edge.src] or 0) >= source.max
        if edge.type == EDGE_SUFFICIENT then
            sufficientEdges = sufficientEdges + 1
            sufficientMet = sufficientMet or active
        elseif not active then
            return false, "prereq"
        end
    end
    if sufficientEdges > 0 and not sufficientMet then
        return false, "prereq"
    end

    local pool = spent[node.group or 0] or {}
    for _, condition in ipairs(node.conds) do
        if condition.level and condition.level > 60 then
            return false, "level"
        end
        if condition.currency and condition.spent and (pool[condition.currency] or 0) < condition.spent then
            return false, "gate"
        end
    end
    return true
end

-- Where each node stands after the first `count` planned points: "maxed", "partial", "available" or "locked".
-- This is what the game's own window shows as full, started, can-be-learned and greyed out.
function TP:NodeStates(meta, order, count)
    count = math.min(count or #order, #order)
    local ranks, spent = {}, {}
    for index = 1, count do
        local nodeID = order[index].n
        local node = meta.nodes[nodeID]
        if node then
            ranks[nodeID] = (ranks[nodeID] or 0) + 1
            Spend(spent, node)
        end
    end

    local states = {}
    for nodeID, node in pairs(meta.nodes) do
        local taken = ranks[nodeID] or 0
        if taken >= node.max then
            states[nodeID] = "maxed"
        elseif count < POINT_CAP and PrerequisitesMet(meta, node, ranks, spent) then
            states[nodeID] = taken > 0 and "partial" or "available"
        else
            states[nodeID] = taken > 0 and "partial" or "locked"
        end
    end
    return states
end

-- How many ranks of a talent the first `count` planned points give it.
function TP:PlannedRank(plan, nodeID, count)
    local rank = 0
    for index = 1, math.min(count or #plan.order, #plan.order) do
        if plan.order[index].n == nodeID then
            rank = rank + 1
        end
    end
    return rank
end

-- Returns true, or false plus the index of the first bad point and why.
function TP:ValidateOrder(meta, order)
    local ranks, spent = {}, {}
    for index, entry in ipairs(order) do
        if index > POINT_CAP then
            return false, index, "cap"
        end
        local node = meta.nodes[entry.n]
        if not node then
            return false, index, "unknown"
        end
        if (ranks[entry.n] or 0) >= node.max then
            return false, index, "max"
        end
        local ok, reason = PrerequisitesMet(meta, node, ranks, spent)
        if not ok then
            return false, index, reason
        end
        ranks[entry.n] = (ranks[entry.n] or 0) + 1
        Spend(spent, node)
    end
    return true
end

------------------------------------------------------------------------------------------------------------------------
-- Plans
------------------------------------------------------------------------------------------------------------------------

function TP:Plans(treeID)
    local plans = self.db.plans[treeID]
    if not plans then
        plans = {}
        self.db.plans[treeID] = plans
    end
    return plans
end

function TP:FindPlan(treeID, name)
    local wanted = string.lower(Trim(name))
    for index, plan in ipairs(self:Plans(treeID)) do
        if string.lower(plan.name) == wanted then
            return plan, index
        end
    end
end

function TP:UniqueName(treeID, base)
    base = Trim(base)
    if base == "" then
        base = "Plan"
    end
    base = base:sub(1, 28)
    if not self:FindPlan(treeID, base) then
        return base
    end
    local suffix = 2
    while self:FindPlan(treeID, base .. " " .. suffix) do
        suffix = suffix + 1
    end
    return base .. " " .. suffix
end

function TP:ActivePlan(treeID)
    local plans = self:Plans(treeID)
    local name = self.db.active[treeID]
    local plan = name and self:FindPlan(treeID, name)
    if not plan and plans[1] then
        plan = plans[1]
        self.db.active[treeID] = plan.name
    end
    return plan
end

function TP:SetActive(treeID, plan)
    self.db.active[treeID] = plan and plan.name or nil
    self.view = nil
end

function TP:NewPlan(treeID, name, order)
    local plan = {
        name = self:UniqueName(treeID, name),
        order = order or {},
        updated = time and time() or 0,
    }
    local plans = self:Plans(treeID)
    plans[#plans + 1] = plan
    self:SetActive(treeID, plan)
    return plan
end

function TP:RenamePlan(treeID, plan, name)
    name = Trim(name):sub(1, 28)
    if name == "" then
        return false
    end
    local existing = self:FindPlan(treeID, name)
    if existing and existing ~= plan then
        return false, "That name is already used."
    end
    local wasActive = self.db.active[treeID] == plan.name
    plan.name = name
    if wasActive then
        self.db.active[treeID] = name
    end
    return true
end

function TP:DeletePlan(treeID, plan)
    local plans = self:Plans(treeID)
    for index, candidate in ipairs(plans) do
        if candidate == plan then
            table.remove(plans, index)
            break
        end
    end
    if self.db.active[treeID] == plan.name then
        self.db.active[treeID] = plans[1] and plans[1].name or nil
    end
    self.view = nil
end

-- Node ids can move when the game is hotfixed, spell ids don't. Re-link points by spell when the node no longer fits.
function TP:ResolvePlan(plan, meta)
    if meta.count == 0 or self.resolved[plan] == meta then
        return
    end
    self.resolved[plan] = meta

    local fixed = {}
    for _, entry in ipairs(plan.order) do
        local node = meta.nodes[entry.n]
        if node and (not entry.s or not node.spell or node.spell == entry.s) then
            fixed[#fixed + 1] = entry
        elseif entry.s and meta.bySpell[entry.s] then
            fixed[#fixed + 1] = { n = meta.bySpell[entry.s], s = entry.s }
        end
    end
    plan.order = fixed
end
TP.resolved = setmetatable({}, { __mode = "k" })

------------------------------------------------------------------------------------------------------------------------
-- Editing a plan. self.view (optional) is how many points the level slider is showing; new points go in after it.
------------------------------------------------------------------------------------------------------------------------

function TP:AddPoint(snap, nodeID)
    local plan = snap.plan
    if not plan then
        return false, "noplan"
    end

    local order = plan.order
    local at = math.min(self.view or #order, #order)
    local node = snap.meta.nodes[nodeID]
    local new = {}
    for i = 1, at do
        new[#new + 1] = order[i]
    end
    new[#new + 1] = { n = nodeID, s = node and node.spell }
    for i = at + 1, #order do
        new[#new + 1] = order[i]
    end

    local ok, _, reason = self:ValidateOrder(snap.meta, new)
    if not ok then
        return false, reason
    end

    plan.order = new
    plan.updated = time and time() or 0
    if self.view then
        self.view = at + 1
        if self.view >= #new then
            self.view = nil
        end
    end
    return true
end

function TP:RemovePoint(snap, nodeID)
    local plan = snap.plan
    if not plan then
        return false, "noplan"
    end

    local order = plan.order
    local from = math.min(self.view or #order, #order)
    local found
    for i = from, 1, -1 do
        if order[i].n == nodeID then
            found = i
            break
        end
    end
    if not found then
        return false, "none"
    end

    local new = {}
    for i, entry in ipairs(order) do
        if i ~= found then
            new[#new + 1] = entry
        end
    end
    if not self:ValidateOrder(snap.meta, new) then
        return false, "dependents"
    end

    plan.order = new
    plan.updated = time and time() or 0
    if self.view then
        self.view = self.view - 1
        if self.view >= #new then
            self.view = nil
        end
    end
    return true
end

------------------------------------------------------------------------------------------------------------------------
-- Snapshot: everything the UI needs to draw one frame
------------------------------------------------------------------------------------------------------------------------

-- snap.actual   = ranks you've bought (including ones staged and not yet applied)
-- snap.nextIndex / snap.nextNode = the first planned point you haven't taken yet
function TP:Snapshot()
    local talentFrame, configID, treeID = self:GetContext()
    if not talentFrame then
        return nil
    end
    if talentFrame.IsInspecting and talentFrame:IsInspecting() then
        return nil
    end

    local meta = self:GetMeta(configID, treeID)
    if meta.count == 0 then
        return nil
    end

    local plan = self:ActivePlan(treeID)
    if plan then
        self:ResolvePlan(plan, meta)
    end

    local snap = { tf = talentFrame, configID = configID, treeID = treeID, meta = meta, plan = plan, actual = {}, spent = 0 }
    if not self.browse then -- another class's tree has nothing bought
        for nodeID in pairs(meta.nodes) do
            local info = C_Traits.GetNodeInfo(configID, nodeID)
            local ranks = info and info.ranksPurchased or 0
            if ranks > 0 then
                snap.actual[nodeID] = ranks
                snap.spent = snap.spent + ranks
            end
        end
    end

    if plan then
        -- Walk the plan, crediting the points you already have. The first point with no credit is your next one,
        -- even if you took things in a different order than planned.
        local credit = {}
        for nodeID, ranks in pairs(snap.actual) do
            credit[nodeID] = ranks
        end
        for index, entry in ipairs(plan.order) do
            if (credit[entry.n] or 0) > 0 then
                credit[entry.n] = credit[entry.n] - 1
            else
                snap.nextIndex = index
                snap.nextNode = entry.n
                break
            end
        end
    end
    return snap
end

function TP:SetMode(mode)
    self.db.mode = mode
    self.view = nil
    if mode == "edit" then
        local _, _, treeID = self:GetContext()
        if treeID and not self:ActivePlan(treeID) then
            self:NewPlan(treeID, "Plan")
        end
    end
    if self.UI then
        self.UI:Refresh()
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Events and slash command
------------------------------------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name == ADDON then
            TP:InitDB()
            TP.UI:Install()
            TP.UI:TryAttach()
        elseif name == "Blizzard_PlayerSpells" or name == "Blizzard_ClassTalentUI" then
            TP.UI:TryAttach()
        end
    elseif event == "PLAYER_LOGIN" then
        TP.UI:TryAttach()
    end
end)

SLASH_TALENTSFORGE1 = "/tforge"
SLASH_TALENTSFORGE2 = "/talentsforge"
SlashCmdList["TALENTSFORGE"] = function(input)
    local command, argument = string.match(string.lower(Trim(input)), "^(%S*)%s*(.-)$")
    if command == "mode" and (argument == "off" or argument == "guide" or argument == "edit") then
        TP:SetMode(argument)
        TP:Print("Mode: " .. argument)
    elseif command == "reset" then
        TP.db.pos = {}
        TP.UI:ResetPositions()
        TP:Print("Moved the chip and the bar back to their default spots.")
    else
        TP:Print("Open your talents and click the chip at the top. Shift-drag the chip or the bar to move them.")
        TP:Print("/tforge mode off|guide|edit  -  switch mode")
        TP:Print("/tforge reset  -  put the chip and bar back where they started")
    end
end
