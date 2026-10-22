-- Talents Forge UI: everything is drawn inside the game's own talent window, in the game's own style.
--   chip    a small pill at the top of the window. Click it for plans, modes, import and export.
--   rings   a ring and a level badge on each talent button (the overlay)
--   bar     the level slider and buttons, only in edit mode
--   sheet   the import / export / name dialog, dimming the tree
--   viewer  another class's tree, laid out as three panels like the game's own
-- Look: Blizzard's panel buttons, close button and input box, the game's font objects, and the bronze border FlareUI uses.
local ADDON, TP = ...
local L = TP.L
local UI = {}
TP.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8x8"
local HILIGHT = "Interface\\Buttons\\ButtonHilight-Square"
local TOOLTIP_BORDER = "Interface\\Tooltips\\UI-Tooltip-Border"
local PANEL_TILE = "Interface\\Collections\\CollectionsBackgroundTile"
local ROUND_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask"

local BRONZE = { 0.65, 0.49, 0.27 }
local BRONZE_MUTED = { 0.61, 0.48, 0.29 }
local GOLD = { 1, 0.82, 0 }
local PLAN = { 0.25, 0.78, 0.70 } -- the colour of everything that is "your plan"
local INK = { 0.02, 0.19, 0.16 }
local RED = { 0.88, 0.48, 0.44 }
local GREEN = { 0.3, 0.9, 0.3 }
local MUTED = { 0.58, 0.53, 0.42 }
local BASE = { 0.045, 0.04, 0.035 } -- the near-black behind a spec background

local AVAILABLE_GLOW = "talents-node-square-greenglow"

local MODES = { { "off", L["Off"] }, { "guide", L["Guide"] }, { "edit", L["Edit"] } }
local STRATA = "DIALOG"

local PANEL_BACKDROP = {
    bgFile = WHITE,
    edgeFile = TOOLTIP_BORDER,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local SMALL_BACKDROP = {
    bgFile = WHITE,
    edgeFile = TOOLTIP_BORDER,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local EDGE_BACKDROP = {
    edgeFile = TOOLTIP_BORDER,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local NODE_BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

------------------------------------------------------------------------------------------------------------------------
-- Small widget helpers
------------------------------------------------------------------------------------------------------------------------

local function NewPanel(parent, alpha, backdrop)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetBackdrop(backdrop or PANEL_BACKDROP)
    frame:SetBackdropColor(0.05, 0.05, 0.05, alpha or 0.95)
    frame:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1)
    return frame
end

-- font: one of the game's font objects, so text matches the rest of the interface.
local function NewText(parent, font, color)
    local text = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    if color then
        text:SetTextColor(color[1], color[2], color[3])
    end
    return text
end

local function HasAtlas(name)
    return name ~= nil and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

-- A Blizzard panel button. SetActive lights it up the way a selected button looks in the game.
local function NewButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, height)
    button:SetText(label)
    button:SetScript("OnClick", onClick)
    -- Wide enough for its label, never narrower than it started.
    button.minWidth = width
    function button:FitText()
        local text = self.GetTextWidth and self:GetTextWidth() or 0
        self:SetWidth(math.max(self.minWidth, text + 24))
    end
    function button:SetActive(active)
        self.active = active and true or false
        if self.active then
            self:LockHighlight()
        else
            self:UnlockHighlight()
        end
    end
    return button
end

-- A flat button in the addon's own look: a dark body and a thin border that warms to bronze when the pointer is on it.
-- SetText(text, tone) also takes a colour for the label (used for the "Sure?" asking).
local function NewFlatButton(parent, label, width, height, onClick)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width, height)
    button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    button.text = NewText(button, "GameFontHighlightSmall")
    button.text:SetPoint("CENTER")

    function button:Restyle()
        local body, edge, ink
        if self.pressed then
            body, edge = { 0.06, 0.05, 0.035 }, BRONZE
        elseif self.hovered then
            body, edge = { 0.14, 0.115, 0.08 }, BRONZE
        else
            body, edge = { 0.09, 0.075, 0.055 }, { 0.24, 0.2, 0.12 }
        end
        ink = self.tone or (self.hovered and { 1, 1, 1 } or { 0.91, 0.85, 0.66 })
        self:SetBackdropColor(body[1], body[2], body[3], 1)
        self:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
        self.text:SetTextColor(ink[1], ink[2], ink[3])
    end
    function button:SetText(text, tone)
        self.text:SetText(text)
        self.tone = tone
        self:Restyle()
    end
    -- Wide enough for the longest of the given labels (other languages run longer), never narrower than it started.
    button.minWidth = width
    function button:Fit(...)
        local widest = self.minWidth
        local current = self.text:GetText()
        for index = 1, select("#", ...) do
            self.text:SetText((select(index, ...)))
            widest = math.max(widest, (self.text:GetStringWidth() or 0) + 18)
        end
        self.text:SetText(current)
        self:SetWidth(widest)
        return widest
    end

    button:SetScript("OnEnter", function(self)
        self.hovered = true
        self:Restyle()
    end)
    button:SetScript("OnLeave", function(self)
        self.hovered, self.pressed = false, false
        self:Restyle()
    end)
    button:SetScript("OnMouseDown", function(self)
        self.pressed = true
        self:Restyle()
    end)
    button:SetScript("OnMouseUp", function(self)
        self.pressed = false
        self:Restyle()
    end)
    button:SetScript("OnClick", onClick)
    button:SetText(label)
    return button
end

-- A small text button at the right end of a menu row. It lights up the row while the pointer is on it.
local function NewLink(row, label, color)
    local link = CreateFrame("Button", nil, row)
    link.text = NewText(link, "GameFontNormalSmall", color)
    link.text:SetPoint("CENTER")
    link.text:SetText(label)
    link:SetSize(link.text:GetStringWidth() + 6, 16)
    link.label, link.color = label, color
    function link:Restyle()
        self.text:SetText(self.label)
        self.text:SetTextColor(self.color[1], self.color[2], self.color[3])
    end
    link:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 1, 1)
        row.hover:Show()
    end)
    link:SetScript("OnLeave", function(self)
        self.text:SetTextColor(self.color[1], self.color[2], self.color[3])
        row.hover:Hide()
    end)
    return link
end

-- Shift-drag to move. The position is saved as an offset from the talent window's centre.
local function MakeMovable(frame, key, tf, defaultPoint)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")

    function frame:Place()
        local saved = TP.db.pos[key]
        self:ClearAllPoints()
        if saved then
            self:SetPoint("CENTER", tf, "CENTER", saved[1], saved[2])
        else
            self:SetPoint(unpack(defaultPoint))
        end
    end

    frame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self.dragging = true
            self:StartMoving()
        end
    end)
    frame:SetScript("OnDragStop", function(self)
        if not self.dragging then
            return
        end
        self.dragging = nil
        self:StopMovingOrSizing()
        local fx, fy = self:GetCenter()
        local tx, ty = tf:GetCenter()
        if fx and tx then
            local scale = self:GetEffectiveScale() / tf:GetEffectiveScale()
            TP.db.pos[key] = { math.floor((fx - tx) * scale + 0.5), math.floor((fy - ty) * scale + 0.5) }
        end
        self:Place()
        if self.onMoved then
            self.onMoved()
        end
    end)
    frame:Place()
end

------------------------------------------------------------------------------------------------------------------------
-- Building the pieces
------------------------------------------------------------------------------------------------------------------------

-- An outline in the shape of the game's own talent frame (chamfered corners), tinted with SetBackdropBorderColor like the
-- plain border it replaces. Falls back to a plain square border when the client doesn't have the art.
local RING_ATLAS = "talents-node-square-gray"
local function NewRing(parent, outset)
    local ring = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    ring:SetPoint("TOPLEFT", -outset, outset)
    ring:SetPoint("BOTTOMRIGHT", outset, -outset)
    if HasAtlas(RING_ATLAS) then
        ring.edge = ring:CreateTexture(nil, "OVERLAY")
        ring.edge:SetAllPoints()
        ring.edge:SetAtlas(RING_ATLAS)
        ring.edge:SetDesaturated(true)
        function ring:SetBackdropBorderColor(red, green, blue, alpha)
            self.edge:SetVertexColor(red, green, blue, alpha or 1)
        end
    else
        ring:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    end
    ring:Hide()
    return ring
end

-- A small glowing sphere: a bright round core inside two softer round halos.
local function NewOrb(parent, size, color)
    local orb = CreateFrame("Frame", nil, parent)
    orb:SetSize(size * 2.6, size * 2.6)
    local function Disc(diameter, alpha, red, green, blue)
        local disc = orb:CreateTexture(nil, "OVERLAY")
        disc:SetTexture(WHITE)
        disc:SetBlendMode("ADD")
        disc:SetSize(diameter, diameter)
        disc:SetPoint("CENTER", orb, "CENTER")
        local mask = orb:CreateMaskTexture()
        mask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(disc)
        disc:AddMaskTexture(mask)
        disc:SetVertexColor(red, green, blue, alpha)
    end
    Disc(size * 2.6, 0.22, color[1], color[2], color[3])
    Disc(size * 1.6, 0.45, color[1], color[2], color[3])
    Disc(size, 1, 1, 1, 0.95)
    return orb
end

-- Things that open (the menu, the dialog) fade in and slide down 6px over 0.14s instead of snapping into place.
local function GlideIn(frame)
    if not frame.glide then
        frame.glide = frame:CreateAnimationGroup()
        local fade = frame.glide:CreateAnimation("Alpha")
        fade:SetFromAlpha(0)
        fade:SetToAlpha(1)
        fade:SetDuration(0.14)
        local slide = frame.glide:CreateAnimation("Translation")
        slide:SetOffset(0, -6)
        slide:SetDuration(0.14)
        slide:SetSmoothing("OUT")
        local function Settle()
            if frame.glideHome then
                frame:ClearAllPoints()
                frame:SetPoint(unpack(frame.glideHome))
                frame.glideHome = nil
            end
        end
        frame.glide:SetScript("OnFinished", Settle)
        frame.glide:SetScript("OnStop", Settle)
    end
    frame.glide:Stop()
    local point, relative, relativePoint, x, y = frame:GetPoint(1)
    if not point then
        return
    end
    frame.glideHome = { point, relative, relativePoint, x or 0, y or 0 }
    frame:ClearAllPoints()
    frame:SetPoint(point, relative, relativePoint, x or 0, (y or 0) + 6) -- starts 6px higher and slides down to where it belongs
    frame.glide:Play()
end

-- ... and fade out and slide up again when they close; `done` hides whatever holds them once the animation has played.
local function GlideOut(frame, done)
    if frame.closing then
        return
    end
    if not frame.glideOutGroup then
        frame.glideOutGroup = frame:CreateAnimationGroup()
        frame.glideOutGroup:SetToFinalAlpha(true)
        local fade = frame.glideOutGroup:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(0.12)
        local slide = frame.glideOutGroup:CreateAnimation("Translation")
        slide:SetOffset(0, 6)
        slide:SetDuration(0.12)
        slide:SetSmoothing("IN")
        frame.glideOutGroup:SetScript("OnFinished", function()
            frame.closing = false
            local finish = frame.glideOutDone
            frame.glideOutDone = nil
            if finish then
                finish()
            end
            frame:SetAlpha(1)
        end)
    end
    if frame.glide then
        frame.glide:Stop()
    end
    frame.closing = true
    frame.glideOutDone = done
    frame.glideOutGroup:Play()
end

-- Opening something that is still closing brings it straight back.
local function CancelGlideOut(frame)
    if frame.closing then
        frame.glideOutGroup:Stop()
        frame.closing = false
        frame.glideOutDone = nil
        frame:SetAlpha(1)
    end
end

function UI:BuildChip(tf)
    local chip = CreateFrame("Button", nil, tf, "BackdropTemplate")
    chip:SetHeight(26)
    chip:SetFrameStrata(STRATA)
    chip:SetFrameLevel(100)
    chip:SetBackdrop(SMALL_BACKDROP)
    chip:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    chip:SetBackdropBorderColor(BRONZE[1], BRONZE[2], BRONZE[3], 1)

    chip.dot = chip:CreateTexture(nil, "OVERLAY")
    chip.dot:SetTexture(WHITE)
    chip.dot:SetSize(7, 7)
    chip.dot:SetPoint("LEFT", 12, 0)

    chip.text = NewText(chip, "GameFontHighlightSmall")
    chip.text:SetPoint("LEFT", chip.dot, "RIGHT", 7, 0)

    chip.more = NewText(chip, "GameFontDisableSmall")
    chip.more:SetPoint("RIGHT", -10, 0)
    chip.more:SetText("...")

    chip:SetScript("OnClick", function()
        UI:ToggleMenu()
    end)
    chip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Talents Forge", 1, 0.82, 0)
        GameTooltip:AddLine(L["Click for plans, modes, import and export."], 1, 1, 1, true)
        GameTooltip:AddLine(L["Shift-drag to move."], 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", GameTooltip_Hide)

    -- embers that rise from the chip when a plan is finished
    chip.embers = {}
    for index = 1, 6 do
        local ember = NewOrb(chip, 4, { 1, 0.62, 0.18 })
        ember:SetFrameLevel(chip:GetFrameLevel() + 5)
        ember:Hide()
        ember.group = ember:CreateAnimationGroup()
        local rise = ember.group:CreateAnimation("Translation")
        rise:SetOffset(0, 32 + (index % 3) * 8)
        rise:SetDuration(1.1)
        rise:SetSmoothing("OUT")
        local fade = ember.group:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0)
        fade:SetDuration(1.1)
        fade:SetSmoothing("IN")
        ember.group:SetScript("OnFinished", function()
            ember:Hide()
        end)
        chip.embers[index] = ember
    end

    MakeMovable(chip, "chip", tf, { "TOP", tf, "TOP", 0, -10 })
    chip.onMoved = function()
        if UI.bar then
            UI.bar:Place()
        end
    end
    self.chip = chip
end

function UI:PlayForgeSparks()
    local chip = self.chip
    if not chip or not chip:IsShown() then
        return
    end
    local width = chip:GetWidth() or 200
    for index, ember in ipairs(chip.embers) do
        ember:ClearAllPoints()
        ember:SetPoint("TOP", chip, "TOP", (index - 3.5) * width / 7, -2)
        C_Timer.After(index * 0.07, function()
            ember.group:Stop()
            ember:Show()
            ember.group:Play()
        end)
    end
end

-- Remembers whether each plan was finished, and when you buy the last planned point, the chip throws sparks.
function UI:TrackCompletion(snap, mode)
    if not snap or not snap.plan or TP.browse then
        return
    end
    local key = snap.treeID .. ":" .. snap.plan.name
    local complete = #snap.plan.order > 0 and snap.nextNode == nil
    self.completion = self.completion or {}
    local previous = self.completion[key]
    local spent = snap.spent
    self.completion[key] = { complete = complete, spent = spent }
    if previous and not previous.complete and complete and mode == "guide" and spent > previous.spent then
        self:PlayForgeSparks()
    end
end

function UI:BuildBar(tf)
    local bar = NewPanel(tf, 0.92, SMALL_BACKDROP)
    bar:SetSize(418, 34)
    bar:SetFrameStrata(STRATA)
    bar:SetFrameLevel(100)
    bar:EnableMouse(true)
    bar:Hide()

    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText("Talents Forge", 1, 0.82, 0)
        GameTooltip:AddLine(L["Shift-drag to move."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", GameTooltip_Hide)

    -- three groups, each separated from the next by a thin rule: points per tree | level slider | buttons
    local function Rule(after, gap)
        local rule = bar:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(BRONZE_MUTED[1], BRONZE_MUTED[2], BRONZE_MUTED[3], 0.6)
        rule:SetSize(1, 20)
        rule:SetPoint("LEFT", after, "RIGHT", gap, 0)
        return rule
    end

    bar.split = NewText(bar, "GameFontHighlight")
    bar.split:SetPoint("LEFT", 12, 0)
    bar.split:SetWidth(80)
    bar.split:SetJustifyH("LEFT")
    local firstRule = Rule(bar.split, 6)

    -- Thin bronze slider, the same one FlareUI draws.
    local slider = CreateFrame("Slider", nil, bar)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(80, 14)
    slider:SetPoint("LEFT", firstRule, "RIGHT", 10, 0)
    slider:SetMinMaxValues(TP.FIRST_LEVEL, 60)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(BRONZE_MUTED[1], BRONZE_MUTED[2], BRONZE_MUTED[3], 0.35)
    track:SetHeight(3)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    slider:SetThumbTexture(WHITE)
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(7, 14)
    thumb:SetVertexColor(0.80, 0.60, 0.34)
    slider:SetScript("OnValueChanged", function(self, value)
        if UI.settingSlider then
            return
        end
        local snap = UI.snap
        if not snap or not snap.plan then
            return
        end
        local count = math.floor(value + 0.5) - (TP.FIRST_LEVEL - 1)
        TP.view = count < #snap.plan.order and count or nil
        UI:Refresh()
    end)
    bar.slider = slider

    bar.levelValue = NewText(bar, "GameFontNormal")
    bar.levelValue:SetPoint("LEFT", slider, "RIGHT", 8, 0)
    bar.levelValue:SetWidth(44)
    bar.levelValue:SetJustifyH("LEFT")
    local secondRule = Rule(bar.levelValue, 4)

    bar.import = NewFlatButton(bar, L["Import"], 52, 22, function() UI:OpenSheet("import") end)
    bar.import:SetPoint("LEFT", secondRule, "RIGHT", 8, 0)
    bar.export = NewFlatButton(bar, L["Export"], 52, 22, function() UI:OpenSheet("export") end)
    bar.export:SetPoint("LEFT", bar.import, "RIGHT", 4, 0)
    bar.clear = NewFlatButton(bar, L["Clear"], 48, 22, function(self)
        if not self.confirm then
            self.confirm = true
            self:SetText(L["Sure?"], RED)
            C_Timer.After(2, function()
                self.confirm = nil
                self:SetText(L["Clear"])
            end)
            return
        end
        self.confirm = nil
        self:SetText(L["Clear"])
        local snap = UI.snap
        if snap and snap.plan then
            snap.plan.order = {}
            TP.view = nil
            UI:Refresh()
        end
    end)
    bar.clear:SetPoint("LEFT", bar.export, "RIGHT", 4, 0)

    -- The buttons are as wide as their words need, and the bar as wide as everything in it.
    local buttonsWidth = bar.import:Fit(L["Import"]) + bar.export:Fit(L["Export"]) + bar.clear:Fit(L["Clear"], L["Sure?"])
    bar:SetWidth(12 + 80 + 6 + 1 + 10 + 80 + 8 + 44 + 4 + 1 + 8 + buttonsWidth + 8 + 12)

    -- right under the chip, wherever the chip is
    MakeMovable(bar, "bar", tf, { "TOP", self.chip, "BOTTOM", 0, -4 })
    self.bar = bar
end

-- Adds the description of one rank of a talent, the way the game's own talent tooltip gets it.
local function AddRankText(entryID, rank)
    local getter = C_TooltipInfo and C_TooltipInfo.GetTraitEntry
    if not getter then
        return false
    end
    local ok, data = pcall(getter, entryID, rank)
    if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
        return false
    end
    local added = false
    for _, line in ipairs(data.lines) do
        local text = line.leftText
        if type(text) == "string" and text ~= "" then
            local red, green, blue = 1, 1, 1
            if line.leftColor and line.leftColor.GetRGB then
                red, green, blue = line.leftColor:GetRGB()
            end
            GameTooltip:AddLine(text, red, green, blue, true)
            added = true
        end
    end
    return added
end

-- In edit mode a talent with several ranks shows what it does at the rank you have planned (and the next one), not at
-- the rank you own. Returns false when there is nothing to show, so the game's own tooltip is used instead.
function UI:ShowPlannedTooltip(owner, nodeID)
    local snap = self.snap
    local node = snap and snap.plan and snap.meta.nodes[nodeID]
    if not node or node.max <= 1 or not node.entry then
        return false
    end
    local count = math.min(TP.view or #snap.plan.order, #snap.plan.order)
    local planned = TP:PlannedRank(snap.plan, nodeID, count)
    if planned <= 0 then
        return false
    end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(TP:NodeName(snap.meta, nodeID), 1, 1, 1)
    GameTooltip:AddLine(L["Planned rank %d/%d"]:format(planned, node.max), PLAN[1], PLAN[2], PLAN[3])
    if not AddRankText(node.entry, planned) then
        return false
    end
    if planned < node.max then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(TALENT_BUTTON_TOOLTIP_NEXT_RANK or L["Next rank:"], GOLD[1], GOLD[2], GOLD[3])
        AddRankText(node.entry, planned + 1)
    end
    return true
end

function UI:BuildOverlay(button)
    local overlay = CreateFrame("Button", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 15)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay.button = button

    overlay.ring = NewRing(overlay, 4)

    overlay.pulse = overlay.ring:CreateAnimationGroup()
    local fade = overlay.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(0.3)
    fade:SetToAlpha(1)
    fade:SetDuration(0.7)
    overlay.pulse:SetLooping("BOUNCE")

    overlay.glow = overlay:CreateTexture(nil, "OVERLAY")
    overlay.glow:SetTexture(HILIGHT)
    overlay.glow:SetBlendMode("ADD")
    overlay.glow:SetPoint("TOPLEFT", -4, 4)
    overlay.glow:SetPoint("BOTTOMRIGHT", 4, -4)
    overlay.glow:SetVertexColor(PLAN[1], PLAN[2], PLAN[3])
    overlay.glow:SetAlpha(0.45)
    overlay.glow:Hide()

    -- It sits on its own frame just under the talent (a child of the talent's parent), so it glows around the talent
    -- instead of washing out its icon.
    overlay.availHost = CreateFrame("Frame", nil, button:GetParent() or button)
    overlay.availHost:SetFrameLevel(math.max(button:GetFrameLevel() - 1, 0))
    overlay.availHost:SetPoint("CENTER", button, "CENTER")
    overlay.availHost:SetSize(1, 1)
    overlay.avail = overlay.availHost:CreateTexture(nil, "BACKGROUND")
    overlay.avail:SetPoint("CENTER", overlay.availHost, "CENTER")
    if HasAtlas(AVAILABLE_GLOW) then
        overlay.avail:SetAtlas(AVAILABLE_GLOW)
        overlay.avail:SetBlendMode("ADD") -- as the game's own Glow: normal blending leaves the atlas's dark core as a shadow
        overlay.availScale = 2.1
    else
        overlay.avail:SetTexture(HILIGHT)
        overlay.avail:SetBlendMode("ADD")
        overlay.avail:SetVertexColor(GREEN[1], GREEN[2], GREEN[3])
        overlay.availScale = 1.5
    end
    overlay.avail:SetAlpha(0.75)
    overlay.availHost:Hide()

    overlay.badge = CreateFrame("Frame", nil, overlay)
    overlay.badge:SetFrameLevel(overlay:GetFrameLevel() + 5)
    overlay.badge:SetHeight(14)
    overlay.badge:SetPoint("TOPLEFT", overlay, "TOPLEFT", -6, 8)
    overlay.badge.bg = overlay.badge:CreateTexture(nil, "BACKGROUND")
    overlay.badge.bg:SetAllPoints()
    overlay.badge.bg:SetColorTexture(PLAN[1], PLAN[2], PLAN[3])
    overlay.badge.text = NewText(overlay.badge, "GameFontHighlightSmall", INK)
    overlay.badge.text:SetPoint("CENTER")
    overlay.badge:Hide()

    -- The count sits on its own frame, above the ring and the badge: a child frame is always drawn over its parent's text,
    -- which is what made the ring cut through "2/3".
    overlay.rankHost = CreateFrame("Frame", nil, overlay)
    overlay.rankHost:SetAllPoints(overlay)
    overlay.rankHost:SetFrameLevel(overlay:GetFrameLevel() + 12)
    overlay.rank = NewText(overlay.rankHost, "NumberFontNormalSmall")
    -- bottom-right corner of the talent, over the outline and not below it (below it, it ran into the talent underneath)
    overlay.rank:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", 4, -4)
    overlay.rank:SetShadowColor(0, 0, 0, 1)
    overlay.rank:SetShadowOffset(1, -1)

    -- When a talent reaches max rank it flares gold and its count pops, as on foreverchanges.pro (there:
    -- 0.55s ease-out, a gold glow fading to nothing, and the count scaling from 1.35x back to 1x).
    overlay.flashHost = CreateFrame("Frame", nil, overlay)
    overlay.flashHost:SetAllPoints(overlay)
    overlay.flashHost:SetFrameLevel(overlay:GetFrameLevel() + 8)
    overlay.flashGlow = overlay.flashHost:CreateTexture(nil, "BACKGROUND")
    overlay.flashGlow:SetPoint("CENTER", overlay.flashHost, "CENTER")
    if HasAtlas(AVAILABLE_GLOW) then
        overlay.flashGlow:SetAtlas(AVAILABLE_GLOW)
        overlay.flashGlow:SetDesaturated(true) -- so the gold tint below isn't mixed with the atlas's green
        overlay.flashScale = 2.1
    else
        overlay.flashGlow:SetTexture(HILIGHT)
        overlay.flashScale = 1.6
    end
    overlay.flashGlow:SetBlendMode("ADD")
    overlay.flashGlow:SetVertexColor(1, 0.82, 0)
    overlay.flashShine = overlay.flashHost:CreateTexture(nil, "OVERLAY")
    overlay.flashShine:SetPoint("TOPLEFT", overlay.flashHost, "TOPLEFT", 2, -2)
    overlay.flashShine:SetPoint("BOTTOMRIGHT", overlay.flashHost, "BOTTOMRIGHT", -2, 2)
    overlay.flashShine:SetColorTexture(1, 0.92, 0.6, 0.55) -- the brightening of the icon
    overlay.flashShine:SetBlendMode("ADD")
    overlay.flashGroup = overlay.flashHost:CreateAnimationGroup()
    local fade = overlay.flashGroup:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.55)
    fade:SetSmoothing("OUT")
    overlay.flashGroup:SetScript("OnFinished", function()
        overlay.flashHost:Hide()
    end)
    overlay.flashHost:Hide()

    overlay.rankColor = { overlay.rank:GetTextColor() }
    if #overlay.rankColor < 3 then
        overlay.rankColor = { 1, 0.82, 0 }
    end
    overlay.rankGroup = overlay.rankHost:CreateAnimationGroup()
    local pop = overlay.rankGroup:CreateAnimation("Scale")
    if pop.SetScaleFrom then
        pop:SetScaleFrom(1.35, 1.35)
        pop:SetScaleTo(1, 1)
        pop:SetOrigin("BOTTOMRIGHT", 0, 0)
        pop:SetDuration(0.55)
        pop:SetSmoothing("OUT")
    end
    overlay.rankGroup:SetScript("OnFinished", function()
        overlay.rank:SetTextColor(overlay.rankColor[1], overlay.rankColor[2], overlay.rankColor[3])
    end)

    -- the glow behind a flash, in any colour; shine = also brighten the icon
    function overlay:PlayFlash(color, shine)
        if TP.db.animations == false then
            return
        end
        local width = self.button:GetWidth() or 40
        self.flashGlow:SetSize(width * self.flashScale, width * self.flashScale)
        self.flashGlow:SetVertexColor(color[1], color[2], color[3])
        self.flashShine:SetShown(shine)
        self.flashGroup:Stop()
        self.flashHost:Show()
        self.flashGroup:Play()
    end

    function overlay:PlayMaxedFlash()
        if TP.db.animations == false then
            return
        end
        self:PlayFlash(GOLD, true)
        self.rank:SetTextColor(1, 1, 1) -- the count flares white, then settles back
        self.rankGroup:Stop()
        self.rankGroup:Play()
    end

    -- Plan ping: a soft teal ring leaves the talent with every point you plan.
    overlay.pingHost = NewRing(overlay, 4)
    overlay.pingHost:SetFrameLevel(overlay:GetFrameLevel() + 6)
    overlay.pingHost:SetBackdropBorderColor(PLAN[1], PLAN[2], PLAN[3], 1)
    overlay.pingGroup = overlay.pingHost:CreateAnimationGroup()
    local grow = overlay.pingGroup:CreateAnimation("Scale")
    if grow.SetScaleFrom then
        grow:SetScaleFrom(1, 1)
        grow:SetScaleTo(1.9, 1.9)
    end
    grow:SetDuration(0.6)
    grow:SetSmoothing("OUT")
    local ringFade = overlay.pingGroup:CreateAnimation("Alpha")
    ringFade:SetFromAlpha(0.9)
    ringFade:SetToAlpha(0)
    ringFade:SetDuration(0.6)
    overlay.pingGroup:SetScript("OnFinished", function()
        overlay.pingHost:Hide()
    end)
    overlay.pingHost:Hide()

    function overlay:PlayPing()
        if TP.db.animations == false then
            return
        end
        self.pingGroup:Stop()
        self.pingHost:Show()
        self.pingGroup:Play()
    end

    -- A talent that has just been opened wakes up: a bright teal flare and a ring.
    function overlay:PlayWake()
        self:PlayFlash({ 0.55, 1, 0.9 }, false)
        self:PlayPing()
    end

    -- A spark runs from this talent to each one it has just opened, and the target wakes up when its spark arrives.
    -- Several can be in the air at once, so they come from a small pool.
    overlay.sparks = {}
    function overlay:PlaySpark(target)
        if TP.db.animations == false then
            return
        end
        local fromX, fromY = self.button:GetCenter()
        local toX, toY = target.button:GetCenter()
        if not (fromX and fromY and toX and toY) then
            target:PlayWake()
            return
        end
        local spark
        for _, candidate in ipairs(self.sparks) do
            if not candidate:IsShown() then
                spark = candidate
                break
            end
        end
        if not spark then
            spark = NewOrb(self, 7, { 0.35, 0.95, 0.85 })
            spark:SetPoint("CENTER", self, "CENTER")
            spark:SetFrameLevel(self:GetFrameLevel() + 14)
            spark.group = spark:CreateAnimationGroup()
            spark.move = spark.group:CreateAnimation("Translation")
            spark.move:SetDuration(0.5)
            spark.move:SetSmoothing("IN")
            spark.group:SetScript("OnFinished", function()
                spark:Hide()
                local arrive = spark.onArrive
                spark.onArrive = nil
                if arrive then
                    arrive()
                end
            end)
            spark:Hide()
            self.sparks[#self.sparks + 1] = spark
        end
        spark.move:SetOffset(toX - fromX, toY - fromY)
        spark.onArrive = function()
            target:PlayWake()
        end
        spark.group:Stop()
        spark:Show()
        spark.group:Play()
    end

    -- Guide mode: a slow shine sweeps across the next talent (a narrow strip, clipped to the talent, every ~2.6s).
    overlay.sheenClip = CreateFrame("Frame", nil, overlay)
    overlay.sheenClip:SetAllPoints(overlay)
    overlay.sheenClip:SetFrameLevel(overlay:GetFrameLevel() + 4)
    overlay.sheenClip:SetClipsChildren(true)
    overlay.sheen = overlay.sheenClip:CreateTexture(nil, "OVERLAY")
    overlay.sheen:SetTexture(WHITE)
    overlay.sheen:SetBlendMode("ADD")
    overlay.sheen:SetVertexColor(1, 1, 1, 0.45)
    overlay.sheen:SetWidth(10)
    overlay.sheen:SetPoint("TOPLEFT", overlay.sheenClip, "TOPLEFT", -14, 8)
    overlay.sheen:SetPoint("BOTTOMLEFT", overlay.sheenClip, "BOTTOMLEFT", -14, -8)
    if overlay.sheen.SetRotation then
        overlay.sheen:SetRotation(math.rad(20))
    end
    overlay.sheenGroup = overlay.sheen:CreateAnimationGroup()
    overlay.sheenGroup:SetLooping("REPEAT")
    overlay.sheenSweep = overlay.sheenGroup:CreateAnimation("Translation")
    overlay.sheenSweep:SetOrder(1)
    overlay.sheenSweep:SetDuration(0.8)
    overlay.sheenSweep:SetSmoothing("IN_OUT")
    local rest = overlay.sheenGroup:CreateAnimation("Alpha") -- a pause between sweeps
    rest:SetOrder(2)
    rest:SetFromAlpha(1)
    rest:SetToAlpha(1)
    rest:SetDuration(1.8)
    overlay.sheenClip:Hide()

    -- Guide mode with "dim the rest" on: every talent but the next one is shaded.
    overlay.dim = overlay:CreateTexture(nil, "ARTWORK")
    overlay.dim:SetAllPoints()
    overlay.dim:SetColorTexture(0, 0, 0, 0.55)
    overlay.dim:Hide()

    overlay:SetScript("OnClick", function(self, mouseButton)
        UI:NodeClicked(self.nodeID, mouseButton, self)
        -- the pointer is still on the talent, so redraw its tooltip for the rank it has now
        if self:IsMouseOver() then
            local enter = self:GetScript("OnEnter")
            if enter then
                enter(self)
            end
        end
    end)
    overlay:SetScript("OnEnter", function(self)
        local original = self.button:GetScript("OnEnter")
        local planned = TP:Mode() == "edit" and UI:ShowPlannedTooltip(self, self.nodeID)
        if original and not planned then
            original(self.button)
        end
        if TP:Mode() == "edit" then
            if not original and not planned then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Talents Forge", PLAN[1], PLAN[2], PLAN[3])
            GameTooltip:AddLine(L["Left-click: plan a point"], 1, 1, 1)
            GameTooltip:AddLine(L["Shift-click: plan every rank"], 1, 1, 1)
            GameTooltip:AddLine(L["Right-click: remove a point"], 1, 1, 1)
            GameTooltip:AddLine(L["Shift-right-click: remove every point"], 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        local original = self.button:GetScript("OnLeave")
        if original then
            original(self.button)
        else
            GameTooltip_Hide()
        end
    end)

    button.TalentsForgeOverlay = overlay
    return overlay
end

------------------------------------------------------------------------------------------------------------------------
-- Menu (opens under the chip)
------------------------------------------------------------------------------------------------------------------------

local MENU_WIDTH = 340
local ROW_HEIGHT = 22
local CLASS_ROW_HEIGHT = 34
local CLASS_PILL_WIDTH = 60

function UI:BuildMenu(tf)
    local catcher = CreateFrame("Button", nil, tf)
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata(STRATA)
    catcher:SetFrameLevel(150)
    catcher:SetScript("OnClick", function() UI:CloseMenu() end)
    catcher:Hide()

    local menu = NewPanel(catcher, 0.97)
    menu:SetWidth(MENU_WIDTH)
    menu:SetFrameStrata(STRATA)
    menu:SetFrameLevel(160)
    menu:EnableMouse(true)

    -- Off / Guide / Edit as one compact pill: a dark track with three segments, the chosen one washed in teal with a line
    -- under it.
    local bar = CreateFrame("Frame", nil, menu, "BackdropTemplate")
    bar:SetPoint("TOPLEFT", 12, -10)
    bar:SetPoint("TOPRIGHT", -12, -10)
    bar:SetHeight(28)
    bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bar:SetBackdropColor(0.09, 0.075, 0.055, 1)
    bar:SetBackdropBorderColor(0.24, 0.2, 0.12, 1)
    menu.modeBar = bar
    menu.modes = {}
    for index, mode in ipairs(MODES) do
        local key = mode[1]
        local segment = CreateFrame("Button", nil, bar)
        segment:SetHeight(22)
        segment.index = index
        segment.wash = segment:CreateTexture(nil, "BACKGROUND")
        segment.wash:SetAllPoints()
        segment.wash:SetColorTexture(PLAN[1], PLAN[2], PLAN[3], 0.17)
        segment.wash:Hide()
        segment.line = segment:CreateTexture(nil, "ARTWORK")
        segment.line:SetColorTexture(PLAN[1], PLAN[2], PLAN[3], 1)
        segment.line:SetHeight(2)
        segment.line:SetPoint("BOTTOMLEFT", 16, 0)
        segment.line:SetPoint("BOTTOMRIGHT", -16, 0)
        segment.line:Hide()
        segment.text = NewText(segment, "GameFontHighlightSmall", MUTED)
        segment.text:SetPoint("CENTER")
        segment.text:SetText(mode[2])
        function segment:SetActive(active)
            self.active = active and true or false
            self.wash:SetShown(self.active)
            self.line:SetShown(self.active)
            local color = self.active and PLAN or MUTED
            self.text:SetTextColor(color[1], color[2], color[3])
        end
        segment:SetScript("OnEnter", function(self)
            if not self.active then
                self.text:SetTextColor(0.91, 0.85, 0.66)
            end
        end)
        segment:SetScript("OnLeave", function(self)
            self:SetActive(self.active)
        end)
        segment:SetScript("OnClick", function()
            TP:SetMode(key)
            UI:RebuildMenu()
        end)
        menu.modes[key] = segment
    end
    -- the thirds follow the width of the track
    bar:SetScript("OnSizeChanged", function(self, width)
        local each = ((width or MENU_WIDTH - 24) - 6) / #MODES
        for key, segment in pairs(menu.modes) do
            segment:ClearAllPoints()
            segment:SetPoint("TOPLEFT", self, "TOPLEFT", 3 + (segment.index - 1) * each, -3)
            segment:SetWidth(each)
        end
    end)
    for key, segment in pairs(menu.modes) do
        segment:SetWidth(((MENU_WIDTH - 24) - 6) / #MODES)
        segment:ClearAllPoints()
        segment:SetPoint("TOPLEFT", bar, "TOPLEFT", 3 + (segment.index - 1) * (((MENU_WIDTH - 24) - 6) / #MODES), -3)
    end

    menu.classRows = {}
    menu.rows = {}
    menu.rules = {}
    menu.catcher = catcher
    self.menu = menu
end

function UI:AcquireRow(index)
    local menu = self.menu
    local row = menu.rows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, menu)
    row:SetHeight(ROW_HEIGHT)
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:SetColorTexture(1, 0.82, 0, 0.08)
    row.hover:Hide()
    row.label = NewText(row, "GameFontHighlight")
    row.label:SetPoint("LEFT", 8, 0)
    row.right = NewText(row, "GameFontDisableSmall")
    row.right:SetPoint("RIGHT", -8, 0)
    -- a plan's row also carries Rename and Delete at its right-hand end
    row.delete = NewLink(row, L["Delete"], RED)
    row.delete:SetPoint("RIGHT", -8, 0)
    row.rename = NewLink(row, L["Rename"], GOLD)
    row.rename:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
    row.delete:Hide()
    row.rename:Hide()

    -- a switch and a second line, for the on/off rows
    row.switch = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.switch:SetSize(30, 16)
    row.switch:SetPoint("LEFT", 10, 0)
    row.switch:SetBackdrop({ bgFile = WHITE, edgeFile = TOOLTIP_BORDER, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    row.switch.knob = row.switch:CreateTexture(nil, "OVERLAY")
    row.switch.knob:SetTexture(WHITE)
    row.switch.knob:SetSize(11, 11)
    row.switch.knobMask = row.switch:CreateMaskTexture()
    row.switch.knobMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    row.switch.knobMask:SetAllPoints(row.switch.knob)
    row.switch.knob:AddMaskTexture(row.switch.knobMask)
    function row.switch:SetOn(on)
        self.knob:ClearAllPoints()
        if on then
            self:SetBackdropColor(0.16, 0.55, 0.5, 1)
            self:SetBackdropBorderColor(PLAN[1], PLAN[2], PLAN[3], 1)
            self.knob:SetPoint("RIGHT", self, "RIGHT", -4, 0)
            self.knob:SetVertexColor(1, 1, 0.95, 1)
        else
            self:SetBackdropColor(0.16, 0.14, 0.1, 1)
            self:SetBackdropBorderColor(BRONZE_MUTED[1], BRONZE_MUTED[2], BRONZE_MUTED[3], 0.7)
            self.knob:SetPoint("LEFT", self, "LEFT", 4, 0)
            self.knob:SetVertexColor(0.8, 0.77, 0.69, 1)
        end
    end
    row.switch:Hide()
    row.hint = NewText(row, "GameFontDisableSmall")
    row.hint:Hide()

    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    menu.rows[index] = row
    return row
end

-- A row of the browse-classes page: class icon in a ring, the class name in its colour, "you" for your own class, and
-- how many plans you have for it. The class on show gets a wash of its colour and an accent bar. "you" and the plan
-- count each have a column of their own, so rows line up whatever they say.
function UI:AcquireClassRow(index)
    local menu = self.menu
    local row = menu.classRows[index]
    if row then
        return row
    end

    row = CreateFrame("Button", nil, menu)
    row:SetHeight(CLASS_ROW_HEIGHT)
    row.wash = row:CreateTexture(nil, "BACKGROUND")
    row.wash:SetAllPoints()
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetAllPoints()
    row.hover:Hide()
    row.bar = row:CreateTexture(nil, "ARTWORK")
    row.bar:SetWidth(3)
    row.bar:SetPoint("TOPLEFT", 0, -4)
    row.bar:SetPoint("BOTTOMLEFT", 0, 4)

    row.ringMask = row:CreateMaskTexture()
    row.ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    row.iconMask = row:CreateMaskTexture()
    row.iconMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    row.ring = row:CreateTexture(nil, "ARTWORK")
    row.ring:SetTexture(WHITE)
    row.ring:SetSize(26, 26)
    row.ring:SetPoint("LEFT", 14, 0)
    row.ring:AddMaskTexture(row.ringMask)
    row.ringMask:SetAllPoints(row.ring)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(21, 21)
    row.icon:SetPoint("CENTER", row.ring, "CENTER")
    row.icon:AddMaskTexture(row.iconMask)
    row.iconMask:SetAllPoints(row.icon)

    row.name = NewText(row, "GameFontHighlight")
    row.name:SetPoint("LEFT", row.ring, "RIGHT", 10, 0)

    row.pill = CreateFrame("Frame", nil, row, "BackdropTemplate")
    row.pill:SetSize(menu.pillWidth or CLASS_PILL_WIDTH, 18)
    row.pill:SetPoint("RIGHT", -12, 0)
    row.pill:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    row.pill:SetBackdropColor(0.09, 0.075, 0.055, 1)
    row.pill:SetBackdropBorderColor(0.24, 0.2, 0.12, 1)
    row.pill.text = NewText(row.pill, "GameFontHighlightSmall")
    row.pill.text:SetPoint("CENTER")
    if not menu.pillWidth then
        -- as wide as the longest count in this language, so the column lines up on every row
        local widest = CLASS_PILL_WIDTH
        for _, text in ipairs({ L["%d plan"]:format(1), L["%d plans"]:format(88) }) do
            row.pill.text:SetText(text)
            widest = math.max(widest, (row.pill.text:GetStringWidth() or 0) + 16)
        end
        menu.pillWidth = widest
        row.pill:SetWidth(widest)
    end
    row.you = NewText(row, "GameFontDisableSmall")
    row.you:SetPoint("RIGHT", row.pill, "LEFT", -10, 0)
    row.you:SetText(L["you"])

    row:SetScript("OnEnter", function(self)
        self.hover:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hover:Hide()
    end)
    menu.classRows[index] = row
    return row
end

function UI:AcquireRule(index)
    local menu = self.menu
    local rule = menu.rules[index]
    if not rule then
        rule = menu:CreateTexture(nil, "ARTWORK")
        rule:SetColorTexture(BRONZE_MUTED[1], BRONZE_MUTED[2], BRONZE_MUTED[3], 0.6)
        rule:SetHeight(1)
        menu.rules[index] = rule
    end
    return rule
end

function UI:ToggleMenu()
    if self.menu and self.menu.catcher:IsShown() then
        self:CloseMenu()
    else
        self:OpenMenu()
    end
end

function UI:CloseMenu()
    local menu = self.menu
    if not menu or not menu.catcher:IsShown() then
        return
    end
    if menu:IsVisible() then
        GlideOut(menu, function()
            menu.catcher:Hide()
        end)
    else
        menu.catcher:Hide() -- the whole window is closed: nothing to animate
    end
end

-- Redraws the menu if it is open, on the page it is on: its contents may have changed under it.
function UI:RebuildMenu()
    local menu = self.menu
    if menu and menu.catcher:IsShown() and not menu.closing then
        self:OpenMenu(self.menuPage)
    end
end

function UI:OpenMenu(page)
    local snap = self.snap
    if not snap then
        return
    end
    self.menuPage = page
    local menu = self.menu
    CancelGlideOut(menu)
    local treeID = snap.treeID
    local browsing = TP.browse ~= nil

    for _, row in ipairs(menu.rows) do
        row:Hide()
    end
    for _, rule in ipairs(menu.rules) do
        rule:Hide()
    end
    for _, row in ipairs(menu.classRows) do
        row:Hide()
    end
    menu.modeBar:SetShown(not browsing and page ~= "classes")
    for key, segment in pairs(menu.modes) do
        segment:SetActive(TP.db.mode == key)
    end

    local y = (browsing or page == "classes") and -10 or -46
    local rowCount, ruleCount = 0, 0

    local function Rule()
        ruleCount = ruleCount + 1
        local rule = self:AcquireRule(ruleCount)
        rule:ClearAllPoints()
        rule:SetPoint("TOPLEFT", 12, y - 3)
        rule:SetPoint("TOPRIGHT", -12, y - 3)
        rule:Show()
        y = y - 7
    end

    -- actions (optional): { rename = fn, delete = fn } puts those two buttons at the right-hand end, after the count.
    local function Row(label, right, onClick, color, actions)
        rowCount = rowCount + 1
        local row = self:AcquireRow(rowCount)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y)
        row:SetPoint("TOPRIGHT", -6, y)
        row:SetHeight(ROW_HEIGHT)
        row.switch:Hide()
        row.hint:Hide()
        row.label:SetText(label)
        local tint = color or { 1, 1, 1 }
        row.label:SetTextColor(tint[1], tint[2], tint[3])
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.label:ClearAllPoints()
        row.label:SetPoint("LEFT", 8, 0)
        row.right:SetText(right or "")
        row.right:ClearAllPoints()
        if actions then
            row.right:SetPoint("RIGHT", row.rename, "LEFT", -10, 0)
            row.label:SetPoint("RIGHT", row.right, "LEFT", -8, 0) -- a long name is cut short before the count
            row.delete.confirm = nil
            row.delete:Restyle()
            row.rename:SetScript("OnClick", actions.rename)
            row.delete:SetScript("OnClick", actions.delete)
            row.rename:Show()
            row.delete:Show()
        else
            row.right:SetPoint("RIGHT", -8, 0)
            row.rename:Hide()
            row.delete:Hide()
        end
        row:SetScript("OnClick", onClick)
        row:Show()
        y = y - ROW_HEIGHT
        return row
    end

    -- A row with a switch at its left, a label and a line of explanation under it.
    local function ToggleRow(label, hint, on, onClick)
        rowCount = rowCount + 1
        local row = self:AcquireRow(rowCount)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 6, y)
        row:SetPoint("TOPRIGHT", -6, y)
        row:SetHeight(36)
        row.rename:Hide()
        row.delete:Hide()
        row.right:SetText("")
        row.label:SetText(label)
        row.label:SetTextColor(1, 1, 1)
        row.label:SetJustifyH("LEFT")
        row.label:ClearAllPoints()
        row.label:SetPoint("TOPLEFT", 50, -5)
        row.hint:SetText(hint)
        row.hint:ClearAllPoints()
        row.hint:SetPoint("TOPLEFT", 50, -20)
        row.hint:Show()
        row.switch:SetOn(on)
        row.switch:Show()
        row:SetScript("OnClick", onClick)
        row:Show()
        y = y - 36
        return row
    end

    local function Finish()
        local wasOpen = menu.catcher:IsShown()
        menu:SetHeight(-y + 10)
        menu:ClearAllPoints()
        menu:SetPoint("TOP", self.chip, "BOTTOM", 0, -4)
        menu.catcher:Show()
        if not wasOpen then
            GlideIn(menu)
        end
    end

    if page == "classes" then
        Row(L["< Back"], L["Browse classes"], function() UI:OpenMenu() end, { 0.6, 0.6, 0.6 })
        Rule()
        for index, entry in ipairs(TP.CLASSES) do
            local own = entry.tree == TP.ownTreeID
            local viewing = (TP.browse == entry.tree) or (own and not browsing)
            local leaves = self:IsOwnWindowTree(entry)
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.token]
            local r, g, b = 1, 1, 1
            if classColor then
                r, g, b = classColor.r, classColor.g, classColor.b
            end

            local row = self:AcquireClassRow(index)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 6, y)
            row:SetPoint("TOPRIGHT", -6, y)
            row.hover:SetColorTexture(r, g, b, 0.08)
            row.wash:SetColorTexture(r, g, b, viewing and 0.16 or 0)
            row.bar:SetColorTexture(r, g, b, 1)
            row.bar:SetShown(viewing)
            row.ring:SetVertexColor(r, g, b, viewing and 1 or 0.55)
            local atlas = "classicon-" .. entry.token:lower()
            if HasAtlas(atlas) then
                row.icon:SetAtlas(atlas)
            else
                row.icon:SetTexture("Interface\\Icons\\ClassIcon_" .. entry.token:sub(1, 1) .. entry.token:sub(2):lower())
            end
            row.name:SetText(TP:ClassName(entry))
            row.name:SetTextColor(r, g, b)
            row.you:SetShown(own)
            local saved = TP.db.plans[entry.tree]
            local count = saved and #saved or 0
            if count > 0 then
                row.pill.text:SetText((count == 1 and L["%d plan"] or L["%d plans"]):format(count))
                row.pill:Show()
            else
                row.pill:Hide()
            end

            row:SetScript("OnClick", function()
                if leaves then
                    UI:CloseViewer()
                else
                    UI:OpenViewer(entry)
                end
            end)
            row:Show()
            y = y - CLASS_ROW_HEIGHT
        end
        Finish()
        return
    end

    if browsing and not TP.host then
        Row(L["< Back to my talents"], nil, function()
            UI:CloseViewer()
        end, { 0.6, 0.6, 0.6 })
    end
    Rule()
    local plans = TP:Plans(treeID)
    if #plans == 0 then
        Row(L["No plans yet"], nil, function() end, { 0.6, 0.6, 0.6 })
    end
    for _, plan in ipairs(plans) do
        local selected = snap.plan == plan
        local row
        row = Row((selected and "> " or "   ") .. plan.name, #plan.order .. "/" .. TP.POINT_CAP, function()
            TP:SetActive(treeID, plan)
            UI:Refresh()
            UI:RebuildMenu()
        end, selected and PLAN or nil, {
            rename = function()
                TP:SetActive(treeID, plan)
                UI:Refresh()
                UI:OpenSheet("rename")
            end,
            delete = function()
                local link = row.delete
                if not link.confirm then
                    -- the first click only asks
                    link.confirm = true
                    link.text:SetText(L["Sure?"])
                    C_Timer.After(2, function()
                        if link.confirm then
                            link.confirm = nil
                            link:Restyle()
                        end
                    end)
                    return
                end
                TP:DeletePlan(treeID, plan)
                UI:Refresh()
                UI:OpenMenu(page)
            end,
        })
    end
    Row(L["+ New plan"], nil, function()
        UI:OpenSheet("new")
    end, GOLD)

    Rule()
    Row(L["Import build..."], nil, function()
        UI:OpenSheet("import")
    end)
    if snap.plan then
        Row(L["Export build..."], nil, function()
            UI:OpenSheet("export")
        end)
    end
    Rule()
    if not browsing then
        ToggleRow(L["Dim other talents"], L["Guide mode only"], TP.db.focus, function()
            TP.db.focus = not TP.db.focus
            UI:Refresh()
            UI:OpenMenu(page)
        end)
    end
    ToggleRow(L["Edit mode animations"], L["Rings, flashes and sparks"], TP.db.animations ~= false, function()
        TP.db.animations = not (TP.db.animations ~= false)
        UI:RebuildMenu()
    end)
    Row(L["Browse other classes..."], nil, function() UI:OpenMenu("classes") end, GOLD)
    Row(L["Settings profile..."], nil, function() UI:OpenProfile("export") end)
    Finish()
end

------------------------------------------------------------------------------------------------------------------------
-- Sheet: import, export, new plan, rename
------------------------------------------------------------------------------------------------------------------------

function UI:BuildSheet(tf)
    local sheet = CreateFrame("Frame", nil, tf)
    sheet:SetAllPoints(tf)
    sheet:SetFrameStrata(STRATA)
    sheet:SetFrameLevel(300)
    sheet:EnableMouse(true)
    sheet:Hide()

    local dim = sheet:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.6)

    sheet:SetScript("OnMouseDown", function()
        UI:CloseSheet()
    end)

    local card = NewPanel(sheet, 0.98)
    card:SetSize(480, 142)
    card:SetPoint("CENTER")
    card:EnableMouse(true)
    sheet.card = card

    sheet.title = NewText(card, "GameFontNormalLarge")
    sheet.title:SetPoint("TOPLEFT", 20, -18)

    sheet.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
    sheet.close:SetPoint("TOPRIGHT", -2, -2)
    sheet.close:SetScript("OnClick", function() UI:CloseSheet() end)

    sheet.tabExport = NewButton(card, L["Export"], 62, 22, function() UI:OpenSheet("export") end)
    sheet.tabExport:FitText()
    sheet.tabExport:SetPoint("TOPRIGHT", -34, -14)
    sheet.tabImport = NewButton(card, L["Import"], 62, 22, function() UI:OpenSheet("import") end)
    sheet.tabImport:FitText()
    sheet.tabImport:SetPoint("RIGHT", sheet.tabExport, "LEFT", -4, 0)

    local edit = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    edit:SetSize(426, 22)
    edit:SetPoint("TOPLEFT", 26, -56)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(4000)
    edit:SetScript("OnEscapePressed", function() UI:CloseSheet() end)
    edit:SetScript("OnEnterPressed", function() UI:SheetAction() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if sheet.mode == "export" then
            if userInput then
                self:SetText(sheet.exportText or "")
                self:HighlightText()
            end
        elseif sheet.mode == "import" then
            UI:ValidateImport(self:GetText())
        end
    end)
    sheet.edit = edit

    sheet.status = NewText(card, "GameFontHighlightSmall", { 0.6, 0.6, 0.6 })
    sheet.status:SetPoint("BOTTOMLEFT", 20, 20)
    sheet.status:SetWidth(330)
    sheet.status:SetJustifyH("LEFT")

    sheet.action = NewButton(card, L["OK"], 92, 24, function() UI:SheetAction() end)
    sheet.action:SetPoint("BOTTOMRIGHT", -18, 14)

    self.sheet = sheet
end

function UI:SetStatus(text, color)
    local status = self.sheet.status
    status:SetText(text or "")
    color = color or { 0.6, 0.6, 0.6 }
    status:SetTextColor(color[1], color[2], color[3])
end

function UI:OpenSheet(mode)
    local snap = self.snap
    local sheet = self.sheet
    if not snap or not sheet then
        return
    end

    CancelGlideOut(sheet.card)
    local wasOpen = sheet:IsShown()
    sheet.mode = mode
    sheet.parsed = nil
    sheet.exportText = nil
    sheet:Show()
    if not wasOpen then
        GlideIn(sheet.card)
    end

    local sharing = mode == "import" or mode == "export"
    sheet.tabExport:SetShown(sharing)
    sheet.tabImport:SetShown(sharing)
    sheet.tabExport:SetActive(mode == "export")
    sheet.tabImport:SetActive(mode == "import")
    sheet.action:SetShown(mode ~= "export")
    sheet.edit:SetText("")

    if mode == "export" then
        sheet.title:SetText(L["Share build"])
        local text, err = TP:Export(snap.plan, snap.meta, self:ClassIDFor(snap.treeID))
        if text then
            sheet.exportText = text
            sheet.edit:SetText(text)
            sheet.edit:SetFocus()
            sheet.edit:HighlightText()
            self:SetStatus(L["Press Ctrl+C to copy. %d points."]:format(#snap.plan.order), PLAN)
        else
            self:SetStatus(TP:ErrorText(err), RED)
        end
    elseif mode == "import" then
        sheet.title:SetText(L["Share build"])
        sheet.action:SetText(L["Import"])
        sheet.edit:SetFocus()
        self:SetStatus(L["Paste a build string."])
    elseif mode == "new" then
        sheet.title:SetText(L["New plan"])
        sheet.action:SetText(L["Create"])
        sheet.edit:SetText(TP:UniqueName(snap.treeID, L["Plan"]))
        sheet.edit:SetFocus()
        sheet.edit:HighlightText()
        self:SetStatus(L["Name your plan."])
    elseif mode == "rename" then
        sheet.title:SetText(L["Rename plan"])
        sheet.action:SetText(L["Rename"])
        sheet.edit:SetText(snap.plan and snap.plan.name or "")
        sheet.edit:SetFocus()
        sheet.edit:HighlightText()
        self:SetStatus(L["Name your plan."])
    end
end

function UI:CloseSheet()
    local sheet = self.sheet
    if not sheet then
        return
    end
    sheet.edit:ClearFocus()
    if sheet:IsShown() and sheet:IsVisible() then
        GlideOut(sheet.card, function()
            sheet:Hide()
        end)
    else
        sheet:Hide()
    end
end

function UI:ClassIDFor(treeID)
    local entry = TP:ClassByTree(treeID)
    return entry and entry.id
end

function UI:ValidateImport(text)
    local sheet = self.sheet
    local snap = self.snap
    sheet.parsed = nil
    sheet.pendingClass = nil
    if not snap or TP.Trim(text) == "" then
        self:SetStatus(L["Paste a build string."])
        return
    end
    local order, err, extra = TP:Decode(text, snap.meta, self:ClassIDFor(snap.treeID))
    if not order then
        local other = err == "class" and TP:ClassByID(extra)
        if other then
            -- A build for another class: the Import button opens that class's tree, then the string checks out.
            sheet.pendingClass = other
            self:SetStatus(L["This build is for %s. Import opens their tree."]:format(TP:ClassName(other)), GOLD)
        else
            self:SetStatus(TP:ErrorText(err, extra), RED)
        end
        return
    end
    sheet.parsed = order
    local split = TP:Split(snap.meta, order)
    self:SetStatus(L["Valid build. %s, %d points."]:format(table.concat(split, " / "), #order), PLAN)
end

function UI:SheetAction()
    local sheet = self.sheet
    local snap = self.snap
    if not snap or not sheet:IsShown() then
        return
    end

    if sheet.mode == "import" then
        if sheet.pendingClass then
            local entry, text = sheet.pendingClass, sheet.edit:GetText()
            if self:IsOwnWindowTree(entry) then
                self:CloseViewer()
            else
                self:OpenViewer(entry)
            end
            self:OpenSheet("import")
            sheet.edit:SetText(text)
            return
        end
        if not sheet.parsed then
            self:SetStatus(L["Paste a valid build string first."], RED)
            return
        end
        local plan = TP:NewPlan(snap.treeID, L["Imported"], sheet.parsed)
        if not TP.browse and TP.db.mode == "off" then
            TP.db.mode = "guide"
        end
        TP:Print(L["Imported \"%s\" (%d points)."]:format(plan.name, #plan.order))
    elseif sheet.mode == "new" then
        local plan = TP:NewPlan(snap.treeID, sheet.edit:GetText())
        if not TP.browse and TP.db.mode == "off" then
            TP.db.mode = "edit"
        end
        TP:Print(L["Created \"%s\"."]:format(plan.name))
    elseif sheet.mode == "rename" and snap.plan then
        local ok, message = TP:RenamePlan(snap.treeID, snap.plan, sheet.edit:GetText())
        if not ok then
            self:SetStatus(message or L["Enter a name."], RED)
            return
        end
    else
        return
    end
    self:CloseSheet()
    self:Refresh()
    self:RebuildMenu()
end

------------------------------------------------------------------------------------------------------------------------
-- Clicking talents in edit mode
------------------------------------------------------------------------------------------------------------------------

function UI:NodeClicked(nodeID, mouseButton, overlay)
    if TP:Mode() ~= "edit" or not nodeID then
        return
    end
    local snap = TP:Snapshot()
    if not snap then
        return
    end
    if not snap.plan then
        TP:NewPlan(snap.treeID, L["Plan"])
        snap = TP:Snapshot()
        if not snap then
            return
        end
    end

    local justMaxed, added, statesBefore = false, false, nil
    if mouseButton == "RightButton" then
        local ok, reason = TP:RemovePoint(snap, nodeID)
        if not ok then
            TP:Error(TP:ErrorText(reason))
        elseif IsShiftKeyDown() then
            -- Shift-right-click takes out every point of the talent. It stops quietly at the first one that something
            -- else depends on.
            while TP:RemovePoint(snap, nodeID) do
            end
        end
    else
        local node = snap.meta.nodes[nodeID]
        local times = IsShiftKeyDown() and node and node.max or 1
        local function Shown()
            return math.min(TP.view or #snap.plan.order, #snap.plan.order)
        end
        local before = TP:PlannedRank(snap.plan, nodeID, Shown())
        statesBefore = TP:NodeStates(snap.meta, snap.plan.order, Shown())
        for attempt = 1, times do
            local ok, reason = TP:AddPoint(snap, nodeID)
            if not ok then
                if attempt == 1 or not IsShiftKeyDown() then
                    TP:Error(TP:ErrorText(reason))
                end
                break
            end
        end
        -- the point that fills a talent gets the flash
        local after = TP:PlannedRank(snap.plan, nodeID, Shown())
        justMaxed = node ~= nil and before < node.max and after >= node.max
        added = after > before
    end
    self:Refresh()
    if justMaxed and overlay and overlay.PlayMaxedFlash then
        overlay:PlayMaxedFlash()
    elseif added and overlay and overlay.PlayPing then
        overlay:PlayPing()
    end
    if added then
        self:PlayUnlocks(snap, nodeID, statesBefore)
    end
end

-- The overlay of a talent, in whichever window is showing.
function UI:OverlayFor(nodeID)
    local frame = TP.browse and self.viewer or self.tf
    if not frame or not frame.EnumerateAllTalentButtons then
        return nil
    end
    for button in frame:EnumerateAllTalentButtons() do
        local info = button.GetNodeInfo and button:GetNodeInfo()
        if info and info.ID == nodeID then
            return button.TalentsForgeOverlay
        end
    end
end

-- A talent this point has just opened wakes up, and every talent that leads to it (and is full) sends a spark to it. If
-- the point opened a whole row, each talent in the row gets sparks from the talents it is connected to, whichever of them
-- was clicked. A talent opened only by a row's point gate has nothing leading to it, so it just wakes.
function UI:PlayUnlocks(snap, nodeID, before)
    if not before or TP.db.animations == false then
        return
    end
    local count = math.min(TP.view or #snap.plan.order, #snap.plan.order)
    local after = TP:NodeStates(snap.meta, snap.plan.order, count)
    local sent = 0
    for targetID, state in pairs(after) do
        if state == "available" and before[targetID] == "locked" then
            local target = self:OverlayFor(targetID)
            if target then
                local fed = false
                for _, edge in ipairs(snap.meta.nodes[targetID].incoming) do
                    if after[edge.src] == "maxed" and sent < 16 then
                        local source = self:OverlayFor(edge.src)
                        if source and source.PlaySpark then
                            sent = sent + 1
                            fed = true
                            source:PlaySpark(target)
                        end
                    end
                end
                if not fed then
                    target:PlayWake()
                end
            end
        end
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Refreshing what's on screen
------------------------------------------------------------------------------------------------------------------------

-- For each node among the first `count` planned points: how many ranks are planned, and the levels at which the ranks
-- you haven't bought yet would be taken.
local function PlanStats(snap, count)
    local stats, seen = {}, {}
    for index = 1, count do
        local nodeID = snap.plan.order[index].n
        seen[nodeID] = (seen[nodeID] or 0) + 1
        local record = stats[nodeID]
        if not record then
            record = {}
            stats[nodeID] = record
        end
        record.planned = seen[nodeID]
        if seen[nodeID] > (snap.actual[nodeID] or 0) then
            local level = TP:LevelOf(index)
            record.first = record.first or level
            record.last = level
        end
    end
    return stats
end

-- The planned points after the first `from`: the level of the first one for each talent. They are what the slider has
-- hidden, shown as ghosts.
local function FutureStats(snap, from)
    local future = {}
    for index = from + 1, #snap.plan.order do
        local nodeID = snap.plan.order[index].n
        if not future[nodeID] then
            future[nodeID] = TP:LevelOf(index)
        end
    end
    return future
end

local function Truncate(text, length)
    if #text > length then
        return text:sub(1, length - 1) .. "..."
    end
    return text
end

function UI:RefreshChip(snap, mode)
    local chip = self.chip
    if not snap then
        chip:Hide()
        return
    end
    chip:Show()

    local plan = snap.plan
    local text
    if not plan then
        text = L["Talents Forge: no plan yet"]
    elseif mode == "edit" then
        local browsed = TP.browse and TP:ClassByTree(TP.browse)
        local prefix = browsed and (TP:ClassName(browsed) .. ":  ") or (L["Editing"] .. "  ")
        text = prefix .. Truncate(plan.name, 18) .. "  " .. #plan.order .. "/" .. TP.POINT_CAP
    elseif mode == "guide" then
        if snap.nextNode then
            text = L["Next: %s  (level %d)"]:format(TP:NodeName(snap.meta, snap.nextNode), TP:LevelOf(snap.nextIndex))
        elseif #plan.order == 0 then
            text = L["%s is empty"]:format(Truncate(plan.name, 18))
        else
            text = L["%s complete"]:format(Truncate(plan.name, 18))
        end
    else
        text = Truncate(plan.name, 24)
    end

    chip.text:SetText(text)
    chip:SetWidth(math.max(120, chip.text:GetStringWidth() + 58))

    local active = mode ~= "off" and plan ~= nil
    local finished = plan ~= nil and mode == "guide" and snap.nextNode == nil and #plan.order > 0
    local color = finished and GOLD or (active and PLAN or BRONZE)
    chip.dot:SetVertexColor(color[1], color[2], color[3])
    chip:SetBackdropBorderColor(color[1], color[2], color[3], 1)
end

function UI:RefreshBar(snap, mode)
    local bar = self.bar
    if not snap or mode ~= "edit" or not snap.plan then
        bar:Hide()
        return
    end
    bar:Show()

    local order = snap.plan.order
    local view = TP.view
    local count = view or #order
    bar.split:SetText(table.concat(TP:Split(snap.meta, order, count), " / "))

    -- The slider ends at the plan's last point, so dragging to the end stays at the end instead of jumping to level 60.
    local lastLevel = math.max(TP.FIRST_LEVEL, TP:LevelOf(#order))
    self.settingSlider = true
    bar.slider:SetMinMaxValues(TP.FIRST_LEVEL, lastLevel)
    bar.slider:SetValue(view and TP:LevelOf(view) or lastLevel)
    self.settingSlider = nil
    bar.levelValue:SetText(#order == 0 and "-" or L["Lv %d"]:format(TP:LevelOf(count)))
end

-- frame: the game's talent window, or the class browser. snap is nil to clear the frame's overlays.
function UI:RefreshOverlays(frame, snap, mode)
    local tf = frame
    if not tf or not tf.EnumerateAllTalentButtons then
        return
    end

    local editing = snap and mode == "edit" and snap.plan ~= nil
    local guiding = snap and mode == "guide" and snap.plan ~= nil and snap.nextNode ~= nil
    local stats, states, future
    if editing then
        local count = math.min(TP.view or #snap.plan.order, #snap.plan.order)
        stats = PlanStats(snap, count)
        states = TP:NodeStates(snap.meta, snap.plan.order, count) -- what could be taken after those points
        if TP.view and TP.view < #snap.plan.order then
            future = FutureStats(snap, count)
        end
    end

    for button in tf:EnumerateAllTalentButtons() do
        local info = button.GetNodeInfo and button:GetNodeInfo()
        local nodeID = info and info.ID
        local overlay = button.TalentsForgeOverlay
        local known = snap and nodeID and snap.meta.nodes[nodeID]

        if not known or not (editing or guiding) then
            if overlay then
                overlay:Hide()
                overlay.availHost:Hide()
                overlay.sheenGroup:Stop()
                overlay.sheenClip:Hide()
                overlay.dim:Hide()
            end
        else
            overlay = overlay or self:BuildOverlay(button)
            overlay.nodeID = nodeID
            overlay:Show()
            overlay:EnableMouse(editing)

            local ring, badge, glow = overlay.ring, overlay.badge, overlay.glow
            local show = false
            local isNext = false
            local ghost = false

            local state = states and states[nodeID]
            local canTake = state == "available" or state == "partial"
            if canTake then
                local width = overlay.button:GetWidth() or 40
                overlay.avail:SetSize(width * overlay.availScale, width * overlay.availScale)
            end
            overlay.availHost:SetShown(canTake)

            if editing then
                local record = stats[nodeID]
                local actual = snap.actual[nodeID] or 0
                if record and record.planned > 0 then
                    show = true
                    local color = record.planned > actual and PLAN or GOLD
                    ring:SetBackdropBorderColor(color[1], color[2], color[3], 1)
                    overlay.rank:SetText(record.planned .. "/" .. snap.meta.nodes[nodeID].max)
                    overlay.rank:Show()
                    if record.first then
                        local label = record.first == record.last and tostring(record.first) or (record.first .. "-" .. record.last)
                        badge.text:SetText(label)
                        badge:SetWidth(badge.text:GetStringWidth() + 8)
                        badge:Show()
                    else
                        badge:Hide()
                    end
                elseif future and future[nodeID] then
                    -- planned for a later level than the slider shows: a faint ghost of its ring and badge
                    show = true
                    ghost = true
                    ring:SetBackdropBorderColor(PLAN[1], PLAN[2], PLAN[3], 1)
                    overlay.rank:Hide()
                    badge.text:SetText(tostring(future[nodeID]))
                    badge:SetWidth(badge.text:GetStringWidth() + 8)
                    badge:Show()
                else
                    overlay.rank:Hide()
                    badge:Hide()
                end
            else
                overlay.rank:Hide()
                if nodeID == snap.nextNode then
                    show = true
                    isNext = true
                    ring:SetBackdropBorderColor(0.6, 1, 0.95, 1)
                    badge.text:SetText(tostring(TP:LevelOf(snap.nextIndex)))
                    badge:SetWidth(badge.text:GetStringWidth() + 8)
                    badge:Show()
                else
                    badge:Hide()
                end
            end

            ring:SetShown(show)
            glow:SetShown(isNext)
            badge:SetAlpha(ghost and 0.5 or 1)
            if isNext then
                if not overlay.pulse:IsPlaying() then
                    overlay.pulse:Play()
                end
            else
                overlay.pulse:Stop()
                ring:SetAlpha(ghost and 0.35 or 1)
            end

            -- Guide mode: a shine sweeps over the next talent, and the rest can be dimmed.
            overlay.dim:SetShown(guiding and TP.db.focus and not isNext)
            if guiding and isNext then
                overlay.sheenSweep:SetOffset((overlay.button:GetWidth() or 40) + 28, 0)
                overlay.sheenClip:Show()
                if not overlay.sheenGroup:IsPlaying() then
                    overlay.sheenGroup:Play()
                end
            else
                overlay.sheenGroup:Stop()
                overlay.sheenClip:Hide()
            end
        end
    end
end

function UI:Refresh()
    if not self.tf or not self.tf:IsShown() then
        return
    end

    local snap = TP:Snapshot()
    self.snap = snap
    local mode = TP:Mode()
    local browsing = TP.browse ~= nil

    if not snap then
        self:CloseMenu()
        self:CloseSheet()
    end
    self:RefreshChip(snap, mode)
    self:RefreshBar(snap, mode)
    self:TrackCompletion(snap, mode)
    -- While another class is open, the game's own window is covered and gets no overlays.
    self:RefreshOverlays(self.tf, not browsing and snap or nil, mode)
    if browsing then
        self:RefreshViewer(snap, mode)
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Class browser: another class's tree, laid out like the game's own window (three panels, spec headers, locked talents
-- greyed, available ones outlined), drawn from what the game says about it. Planning only; nothing is ever spent.
-- It reuses the overlay, bar, menu and sheet: while it is open TP.browse holds the tree id and the snapshot describes it.
------------------------------------------------------------------------------------------------------------------------

-- The game's own talent art, used when this client has it: the same square frames and arrows as the default window.
local NODE_ATLAS = {
    locked = "talents-node-square-locked",
    available = "talents-node-square-green",
    partial = "talents-node-square-green",
    maxed = "talents-node-square-yellow",
}
local ARROW_HEAD_ATLAS = "talents-arrow-head-locked"

local HEADER_HEIGHT = 84
local PANEL_TOP, PANEL_BOTTOM, PANEL_MARGIN, PANEL_GAP = 62, 58, 14, 8
local MISSING_ICON = 134400 -- the question mark

-- Painted backgrounds, if this client has atlases for them.
-- The game names them talents-background-<class>-<spec> (checked for druid-balance); multi-word specs may be joined,
-- hyphenated, or shortened to the first word, so each form is tried.
local function FindSpecArt(entry, index)
    if not (C_Texture and C_Texture.GetAtlasInfo) then
        return nil
    end
    local class = entry.token:lower()
    local spec = entry.specs[index]:lower()
    local forms = { (spec:gsub("%s+", "")), (spec:gsub("%s+", "-")), spec:match("^(%S+)") }
    for _, form in ipairs(forms) do
        local name = "talents-background-" .. class .. "-" .. form
        if C_Texture.GetAtlasInfo(name) then
            return name
        end
    end
end

-- The game's own window paints one wide picture per class behind all three trees ("talent-background-<class>").
local function FindClassArt(entry)
    local name = "talent-background-" .. entry.token:lower()
    if HasAtlas(name) then
        return name
    end
end

function UI:BuildViewer(tf)
    local viewer = NewPanel(tf, 1)
    viewer:SetAllPoints(tf)
    viewer:SetFrameStrata(STRATA)
    viewer:SetFrameLevel(60)
    viewer:EnableMouse(true)
    viewer:Hide()

    viewer.title = NewText(viewer, "GameFontNormalHuge")
    viewer.title:SetPoint("TOPLEFT", 22, -16)
    viewer.note = NewText(viewer, "GameFontDisableSmall")
    viewer.note:SetPoint("TOPLEFT", viewer.title, "BOTTOMLEFT", 0, -3)
    viewer.note:SetText(L["Planning only. Your own talents aren't touched."])

    viewer.back = NewButton(viewer, L["Back to my talents"], 140, 24, function()
        UI:CloseViewer()
    end)
    viewer.back:FitText()
    viewer.back:SetPoint("TOPRIGHT", -22, -14)

    viewer.empty = NewText(viewer, "GameFontNormal", RED)
    viewer.empty:SetPoint("CENTER")
    viewer.empty:SetText(L["The game didn't describe this class's talents."])
    viewer.empty:Hide()

    -- Connections live above the panels' backgrounds and below the talents.
    viewer.lineHost = CreateFrame("Frame", nil, viewer)
    viewer.lineHost:SetAllPoints(viewer)
    viewer.lineHost:SetFrameLevel(viewer:GetFrameLevel() + 3)

    viewer.panels, viewer.buttonList, viewer.pool, viewer.lines = {}, {}, {}, {}

    -- The same call the game's window answers, so RefreshOverlays treats both alike.
    function viewer:EnumerateAllTalentButtons()
        local index = 0
        return function()
            index = index + 1
            return self.buttonList[index]
        end
    end

    viewer:SetScript("OnSizeChanged", function()
        UI:LayoutViewer()
    end)

    -- In our own window (below the level talents unlock) the browser is all there is, and it can be dragged by its background.
    viewer:RegisterForDrag("LeftButton")
    viewer:SetScript("OnDragStart", function()
        if TP.host then
            TP.host:StartMoving()
        end
    end)
    viewer:SetScript("OnDragStop", function()
        local host = TP.host
        if host then
            host:StopMovingOrSizing()
            local hx, hy = host:GetCenter()
            local ux, uy = UIParent:GetCenter()
            if hx and ux then
                TP.db.pos.host = { math.floor(hx - ux + 0.5), math.floor(hy - uy + 0.5) }
            end
            host:Place()
        end
    end)
    self.viewer = viewer
end

function UI:AcquirePanel(index)
    local viewer = self.viewer
    local panel = viewer.panels[index]
    if panel then
        return panel
    end

    -- The class picture is one big texture laid across the whole window. Each panel clips it to its own area, so the
    -- game maps the picture itself (no texture coordinates of ours involved).
    local clip = CreateFrame("Frame", nil, viewer)
    clip:SetFrameLevel(viewer:GetFrameLevel() + 1)
    clip:SetClipsChildren(true)
    clip.base = clip:CreateTexture(nil, "BACKGROUND")
    clip.base:SetAllPoints()
    clip.base:SetColorTexture(BASE[1], BASE[2], BASE[3], 0.97)
    clip.host = CreateFrame("Frame", nil, clip)
    clip.picture = clip.host:CreateTexture(nil, "ARTWORK")
    clip.picture:SetAllPoints()
    clip:Hide()

    panel = CreateFrame("Frame", nil, viewer, "BackdropTemplate")
    panel.clip = clip
    panel:SetFrameLevel(viewer:GetFrameLevel() + 2)
    panel:SetBackdrop(EDGE_BACKDROP)
    panel:SetBackdropBorderColor(BRONZE_MUTED[1], BRONZE_MUTED[2], BRONZE_MUTED[3], 0.8)

    panel.bg = panel:CreateTexture(nil, "BACKGROUND")
    panel.bg:SetPoint("TOPLEFT", 3, -3)
    panel.bg:SetPoint("BOTTOMRIGHT", -3, 3)
    panel.bg:SetTexture(PANEL_TILE, "REPEAT", "REPEAT")
    panel.bg:SetHorizTile(true)
    panel.bg:SetVertTile(true)

    panel.art = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    panel.art:SetPoint("TOPLEFT", 3, -3)
    panel.art:SetPoint("BOTTOMRIGHT", -3, 3)
    panel.art:SetAlpha(0.55)
    panel.art:Hide()

    panel.base = panel:CreateTexture(nil, "BACKGROUND", nil, 0)
    panel.base:SetPoint("TOPLEFT", 3, -3)
    panel.base:SetPoint("BOTTOMRIGHT", -3, 3)
    panel.base:SetColorTexture(BASE[1], BASE[2], BASE[3], 0)

    -- softens the bottom edge of a background picture that is shorter than the panel
    panel.fade = panel:CreateTexture(nil, "BACKGROUND", nil, 1)
    panel.fade:SetHeight(90)
    panel.fade:Hide()

    panel.wash = panel:CreateTexture(nil, "BACKGROUND", nil, 2)
    panel.wash:SetPoint("TOPLEFT", 3, -3)
    panel.wash:SetPoint("BOTTOMRIGHT", -3, 3)
    panel.wash:SetColorTexture(0, 0, 0, 0.55)

    panel.tint = panel:CreateTexture(nil, "BACKGROUND", nil, 3)
    panel.tint:SetPoint("TOPLEFT", 3, -3)
    panel.tint:SetPoint("TOPRIGHT", -3, -3)
    panel.tint:SetHeight(HEADER_HEIGHT)

    -- spec icon in a round bronze ring, name, and the count of planned points in this tree
    panel.ringMask = panel:CreateMaskTexture()
    panel.ringMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    panel.iconMask = panel:CreateMaskTexture()
    panel.iconMask:SetTexture(ROUND_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")

    panel.ring = panel:CreateTexture(nil, "ARTWORK")
    panel.ring:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 1)
    panel.ring:SetSize(46, 46)
    panel.ring:SetPoint("TOPLEFT", 18, -14)
    panel.ring:AddMaskTexture(panel.ringMask)
    panel.ringMask:SetAllPoints(panel.ring)

    panel.icon = panel:CreateTexture(nil, "OVERLAY")
    panel.icon:SetSize(40, 40)
    panel.icon:SetPoint("CENTER", panel.ring, "CENTER")
    panel.icon:AddMaskTexture(panel.iconMask)
    panel.iconMask:SetAllPoints(panel.icon)

    panel.title = NewText(panel, "GameFontHighlightLarge")
    panel.title:SetPoint("LEFT", panel.ring, "RIGHT", 12, 0)

    panel.count = NewText(panel, "GameFontNormal")
    panel.count:SetPoint("CENTER", panel.ring, "BOTTOMRIGHT", -3, 3)
    panel.count:SetShadowColor(0, 0, 0, 1)
    panel.count:SetShadowOffset(1, -1)

    panel.divider = panel:CreateTexture(nil, "ARTWORK")
    panel.divider:SetColorTexture(BRONZE[1], BRONZE[2], BRONZE[3], 0.5)
    panel.divider:SetHeight(1)
    panel.divider:SetPoint("TOPLEFT", 14, -(HEADER_HEIGHT - 10))
    panel.divider:SetPoint("TOPRIGHT", -14, -(HEADER_HEIGHT - 10))

    viewer.panels[index] = panel
    return panel
end

function UI:AcquireNodeButton(index)
    local viewer = self.viewer
    local button = viewer.pool[index]
    if button then
        return button
    end

    button = CreateFrame("Button", nil, viewer, "BackdropTemplate")
    button:SetFrameLevel(viewer:GetFrameLevel() + 6)
    button:SetBackdrop(NODE_BACKDROP)
    button:SetBackdropColor(0.04, 0.04, 0.04, 1)
    button.inViewer = true
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetPoint("TOPLEFT", 1, -1)
    button.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button.frame = button:CreateTexture(nil, "OVERLAY")
    button.frame:SetAllPoints(button)
    button.frame:Hide()

    function button:GetNodeInfo()
        return { ID = self.nodeID }
    end
    button:SetScript("OnEnter", function(self)
        local snap = UI.snap
        local node = snap and snap.meta.nodes[self.nodeID]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if node and node.spell and GameTooltip.SetSpellByID then
            GameTooltip:SetSpellByID(node.spell)
        else
            GameTooltip:SetText(TP:NodeName(snap and snap.meta, self.nodeID), 1, 0.82, 0)
        end
        if node and node.max > 1 then
            GameTooltip:AddLine(L["Max rank %d"]:format(node.max), 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)

    viewer.pool[index] = button
    return button
end

-- How far apart neighbouring talents usually sit, in the tree's own units: the median of each node's distance to its
-- nearest neighbour. Robust against a few talents that happen to be placed close together.
local function TypicalSpacing(nodes)
    local list = {}
    for _, node in pairs(nodes) do
        list[#list + 1] = node
    end
    local nearest = {}
    for i = 1, #list do
        local best = math.huge
        for j = 1, #list do
            if i ~= j then
                local dx, dy = list[i].x - list[j].x, list[i].y - list[j].y
                local distance = math.sqrt(dx * dx + dy * dy)
                if distance > 0.5 and distance < best then
                    best = distance
                end
            end
        end
        if best < math.huge then
            nearest[#nearest + 1] = best
        end
    end
    if #nearest == 0 then
        return nil
    end
    table.sort(nearest)
    return nearest[math.floor(#nearest / 2) + 1]
end

function UI:LayoutViewer(snap)
    local viewer = self.viewer
    snap = snap or self.snap
    if not viewer or not snap or not TP.browse then
        return
    end
    local meta = snap.meta
    local width, height = viewer:GetWidth(), viewer:GetHeight()
    if not width or not height or width < 200 or height < 200 then
        return
    end

    local key = tostring(meta.treeID) .. ":" .. math.floor(width) .. "x" .. math.floor(height)
    if viewer.layoutKey == key and viewer.meta == meta then
        return
    end

    -- One button per node, and a line for every connection.
    if viewer.meta ~= meta then
        viewer.meta = meta
        viewer.nodeButtons = {}
        for i = #viewer.buttonList, 1, -1 do
            viewer.buttonList[i] = nil
        end

        local ids = {}
        for nodeID in pairs(meta.nodes) do
            ids[#ids + 1] = nodeID
        end
        table.sort(ids)

        for index, nodeID in ipairs(ids) do
            local button = self:AcquireNodeButton(index)
            button.nodeID = nodeID
            button.iconSet = false
            button.icon:SetTexture(MISSING_ICON)
            button:Show()
            viewer.buttonList[index] = button
            viewer.nodeButtons[nodeID] = button
        end
        for index = #ids + 1, #viewer.pool do
            viewer.pool[index]:Hide()
        end

        local lineCount = 0
        for _, nodeID in ipairs(ids) do
            for _, targetID in ipairs(meta.nodes[nodeID].out) do
                local target = viewer.nodeButtons[targetID]
                if target then
                    lineCount = lineCount + 1
                    local line = viewer.lines[lineCount]
                    if not line then
                        line = viewer.lineHost:CreateLine(nil, "ARTWORK")
                        line:SetThickness(3)
                        line.head = viewer.lineHost:CreateTexture(nil, "ARTWORK")
                        line.head:Hide()
                        viewer.lines[lineCount] = line
                    end
                    line.src, line.dst = nodeID, targetID
                    line:SetStartPoint("CENTER", viewer.nodeButtons[nodeID])
                    line:SetEndPoint("CENTER", target)
                    line:Show()
                end
            end
        end
        for index = lineCount + 1, #viewer.lines do
            viewer.lines[index]:Hide()
            viewer.lines[index].head:Hide()
        end
    end
    viewer.layoutKey = key
    viewer.nodeFrames = HasAtlas(NODE_ATLAS.locked) and HasAtlas(NODE_ATLAS.available)
    viewer.arrowHeads = HasAtlas(ARROW_HEAD_ATLAS)

    -- Three panels side by side.
    local entry = TP:ClassByTree(meta.treeID)
    local groupCount = math.max(meta.groupCount or 1, 1)
    local panelWidth = (width - 2 * PANEL_MARGIN - PANEL_GAP * (groupCount - 1)) / groupCount
    local panelHeight = height - PANEL_TOP - PANEL_BOTTOM
    local classColor = entry and RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.token]

    for index = 1, groupCount do
        local panel = self:AcquirePanel(index)
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", viewer, "TOPLEFT", PANEL_MARGIN + (index - 1) * (panelWidth + PANEL_GAP), -PANEL_TOP)
        panel:SetSize(panelWidth, panelHeight)
        panel:Show()
        panel.title:SetText(entry and TP:SpecName(entry, index) or "")
        if entry and entry.icons[index] then
            panel.icon:SetTexture("Interface\\Icons\\" .. entry.icons[index])
        end
        if classColor then
            panel.tint:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.14)
        else
            panel.tint:SetColorTexture(1, 1, 1, 0.06)
        end
        local classArt = entry and FindClassArt(entry)
        local art = (not classArt) and entry and FindSpecArt(entry, index)
        if classArt then
            -- One picture across all three panels, each showing its own part: the whole picture, as tall as the panels.
            panel.bg:Hide()
            panel.art:Hide()
            panel.fade:Hide()
            panel.base:SetColorTexture(BASE[1], BASE[2], BASE[3], 0)
            panel.clip:ClearAllPoints()
            panel.clip:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
            panel.clip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -3, 3)
            panel.clip.host:ClearAllPoints()
            panel.clip.host:SetPoint("TOPLEFT", viewer, "TOPLEFT", PANEL_MARGIN, -PANEL_TOP)
            panel.clip.host:SetSize(width - 2 * PANEL_MARGIN, panelHeight)
            panel.clip.picture:SetAtlas(classArt)
            panel.clip:Show()
            panel.wash:SetColorTexture(0, 0, 0, 0.25)
        elseif art then
            panel.clip:Hide()
            panel.bg:Show()
            panel.art:SetAtlas(art)
            -- Show the picture as it is: as wide as the panel, top-aligned, cropped at the bottom if it is taller.
            -- The panel's own dark background shows below it when it is shorter.
            panel.art:ClearAllPoints()
            panel.art:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -3)
            panel.art:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -3)
            local info = C_Texture.GetAtlasInfo(art)
            local artHeight = panelHeight - 6
            if info and info.width and info.height and info.width > 0 and info.height > 0 then
                local left, right = info.leftTexCoord or 0, info.rightTexCoord or 1
                local top, bottom = info.topTexCoord or 0, info.bottomTexCoord or 1
                local naturalHeight = (panelWidth - 6) * info.height / info.width
                if naturalHeight > artHeight then
                    bottom = top + (bottom - top) * artHeight / naturalHeight
                else
                    artHeight = naturalHeight
                end
                panel.art:SetTexCoord(left, right, top, bottom)
            end
            panel.art:SetHeight(artHeight)
            panel.base:SetColorTexture(BASE[1], BASE[2], BASE[3], 0.97)
            -- fade the picture's bottom edge into the dark below it
            panel.fade:Hide()
            if artHeight < panelHeight - 12 and CreateColor and panel.fade.SetGradient then
                panel.fade:ClearAllPoints()
                panel.fade:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -(3 + artHeight - 90))
                panel.fade:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -3, -(3 + artHeight - 90))
                panel.fade:SetColorTexture(1, 1, 1, 1)
                local ok = pcall(panel.fade.SetGradient, panel.fade, "VERTICAL",
                    CreateColor(BASE[1], BASE[2], BASE[3], 0.97), CreateColor(BASE[1], BASE[2], BASE[3], 0))
                if ok then
                    panel.fade:Show()
                end
            end
            panel.art:SetAlpha(1)
            panel.art:Show()
            panel.wash:SetColorTexture(0, 0, 0, 0)
        else
            panel.clip:Hide()
            panel.bg:Show()
            panel.art:Hide()
            panel.fade:Hide()
            panel.base:SetColorTexture(BASE[1], BASE[2], BASE[3], 0)
            panel.wash:SetColorTexture(0, 0, 0, 0.55)
        end
    end
    for index = groupCount + 1, #viewer.panels do
        viewer.panels[index]:Hide()
        viewer.panels[index].clip:Hide()
    end

    -- Which panel each talent belongs to (Core worked it out).
    local groupOf, minGroupX, maxGroupX = {}, {}, {}
    local minY, maxY = math.huge, -math.huge
    for nodeID, node in pairs(meta.nodes) do
        local index = math.min(node.group or 1, groupCount)
        groupOf[nodeID] = index
        minGroupX[index] = math.min(minGroupX[index] or node.x, node.x)
        maxGroupX[index] = math.max(maxGroupX[index] or node.x, node.x)
        minY, maxY = math.min(minY, node.y), math.max(maxY, node.y)
    end

    -- One scale for all three panels. Talents sit as far apart as in the game's own window (72px between neighbours,
    -- 48px icons), shrinking only if a tree would not fit.
    local innerWidth = panelWidth - 40
    local innerHeight = panelHeight - HEADER_HEIGHT - 20
    local spanX = 1
    for index = 1, groupCount do
        if minGroupX[index] then
            spanX = math.max(spanX, maxGroupX[index] - minGroupX[index])
        end
    end
    local spanY = math.max(maxY - minY, 1)
    local spacing = TypicalSpacing(meta.nodes)
    local pitch, size = 72, 48
    local scale = spacing and (pitch / spacing) or 0.06
    scale = math.min(scale, (innerWidth - size) / spanX, (innerHeight - size) / spanY)
    if spacing then
        size = math.max(20, math.min(size, spacing * scale * 0.67))
    end
    local topOffset = PANEL_TOP + HEADER_HEIGHT + 4 + size / 2 + math.max(0, (innerHeight - size - spanY * scale) / 2)

    for _, button in ipairs(viewer.buttonList) do
        local node = meta.nodes[button.nodeID]
        local index = groupOf[button.nodeID]
        local centreX = PANEL_MARGIN + (index - 0.5) * panelWidth + (index - 1) * PANEL_GAP
        local middleX = ((minGroupX[index] or 0) + (maxGroupX[index] or 0)) / 2
        button.px = centreX + (node.x - middleX) * scale
        button.py = topOffset + (node.y - minY) * scale
        button:SetSize(size, size)
        button:ClearAllPoints()
        button:SetPoint("CENTER", viewer, "TOPLEFT", button.px, -button.py)

        -- the game's square frame is drawn over the icon, so the icon sits inside it
        local inset = viewer.nodeFrames and math.floor(size * 0.14 + 0.5) or 1
        button.icon:ClearAllPoints()
        button.icon:SetPoint("TOPLEFT", inset, -inset)
        button.icon:SetPoint("BOTTOMRIGHT", -inset, inset)
    end

    -- Straight-down connections end in an arrow head, like the game's.
    for _, line in ipairs(viewer.lines) do
        line.head:Hide()
        local source, target = line.src and viewer.nodeButtons[line.src], line.dst and viewer.nodeButtons[line.dst]
        if viewer.arrowHeads and source and target and math.abs(source.px - target.px) < 4 and target.py > source.py then
            line.head:SetAtlas(ARROW_HEAD_ATLAS, true)
            line.head:ClearAllPoints()
            line.head:SetPoint("BOTTOM", target, "TOP", 0, 1)
            line.head:Show()
        end
    end
end

function UI:RefreshViewer(snap, mode)
    local viewer = self.viewer
    local entry = TP.browse and TP:ClassByTree(TP.browse)
    if entry then
        local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.token]
        viewer.title:SetText(TP:ClassName(entry))
        if classColor then
            viewer.title:SetTextColor(classColor.r, classColor.g, classColor.b)
        end
    end
    viewer.empty:SetShown(snap == nil)
    if not snap then
        self:RefreshOverlays(viewer, nil, mode)
        return
    end

    self:LayoutViewer(snap)
    self:RefreshOverlays(viewer, snap, mode)

    local order = snap.plan and snap.plan.order or {}
    local count = math.min(TP.view or #order, #order)
    local states = TP:NodeStates(snap.meta, order, count)

    -- points planned in each tree, like the number on the game's spec icons
    local split = TP:Split(snap.meta, order, count)
    for index, panel in ipairs(viewer.panels) do
        panel.count:SetText(split[index] or 0)
    end

    -- Talents look the way the game draws them: greyed when locked, outlined green when you could take a point.
    for _, button in ipairs(viewer.buttonList) do
        if not button.iconSet then
            local node = snap.meta.nodes[button.nodeID]
            local texture = node and node.spell and C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(node.spell)
            if texture then
                button.icon:SetTexture(texture)
                button.iconSet = true
            end
        end
        local state = states[button.nodeID]
        local atlas = NODE_ATLAS[state]
        if viewer.nodeFrames and atlas then
            if not HasAtlas(atlas) then
                atlas = NODE_ATLAS.available -- no gold frame in this client: the green one still reads as planned
            end
            button.frame:SetAtlas(atlas)
            button.frame:Show()
            button:SetBackdropBorderColor(0, 0, 0, 0)
            button:SetBackdropColor(0, 0, 0, 0)
        else
            button.frame:Hide()
        end
        if state == "locked" then
            button.icon:SetDesaturated(true)
            button.icon:SetVertexColor(0.5, 0.5, 0.5)
            if not viewer.nodeFrames then
                button:SetBackdropBorderColor(0.22, 0.2, 0.17, 1)
            end
        else
            button.icon:SetDesaturated(false)
            button.icon:SetVertexColor(1, 1, 1)
            if not viewer.nodeFrames then
                local colour = state == "available" and GREEN or BRONZE
                button:SetBackdropBorderColor(colour[1], colour[2], colour[3], 1)
            end
        end
    end

    -- A connection lights up once the talent it leaves has been planned.
    for _, line in ipairs(viewer.lines) do
        if line.src then
            if states[line.src] == "maxed" then
                line:SetColorTexture(PLAN[1], PLAN[2], PLAN[3], 0.9)
                line.head:SetVertexColor(PLAN[1], PLAN[2], PLAN[3])
            else
                line:SetColorTexture(0.45, 0.4, 0.33, 0.55)
                line.head:SetVertexColor(1, 1, 1)
            end
        end
    end
end

function UI:OpenViewer(entry)
    if not self.viewer or not entry then
        return
    end
    if self:IsOwnWindowTree(entry) then
        self:CloseViewer()
        return
    end

    TP.browse = entry.tree
    TP.view = nil
    self.viewer.meta = nil -- lay it out afresh for this class
    self.viewer:Show()

    local snap = TP:Snapshot()
    if snap and not snap.plan then
        TP:NewPlan(snap.treeID, L["Plan"])
    end
    self:Refresh()
    self:RebuildMenu()
end

-- Your own class's tree is the game's talent window itself, so choosing it means leaving the browser. In our own window
-- (talents not unlocked yet) there is no such window, and your own class is browsed like any other.
function UI:IsOwnWindowTree(entry)
    return entry.tree == TP.ownTreeID and not TP.host
end

function UI:CloseViewer()
    local viewer = self.viewer
    if not viewer then
        return
    end
    local wasBrowsing = TP.browse ~= nil
    TP.browse = nil
    TP.view = nil
    viewer:Hide()
    self:CloseSheet()
    if TP.host then
        self:CloseMenu()
        if TP.host:IsShown() then
            TP.host:Hide() -- the browser is the whole window; its OnHide comes back here with nothing left to do
        end
        return
    end
    if wasBrowsing then
        self:Refresh()
        self:RebuildMenu()
    end
end

function UI:ResetPositions()
    if self.chip then
        self.chip:Place()
        self.bar:Place()
    end
    if TP.host then
        TP.host:Place()
    end
end

-- A profile was imported: put everything where it says and redraw.
function UI:ProfileApplied()
    self:ResetPositions()
    self:Refresh()
    self:RebuildMenu()
end

------------------------------------------------------------------------------------------------------------------------
-- Settings profile: one string for every setting, position and plan. A window of its own, so /tforge profile works
-- wherever you are, with or without the talent window open.
------------------------------------------------------------------------------------------------------------------------

function UI:BuildProfile()
    local card = NewPanel(UIParent, 0.98)
    _G.TalentsForgeProfile = card
    card:SetSize(500, 150)
    card:SetPoint("CENTER", 0, 120)
    card:SetFrameStrata("FULLSCREEN_DIALOG")
    card:SetClampedToScreen(true)
    card:SetMovable(true)
    card:EnableMouse(true)
    card:RegisterForDrag("LeftButton")
    card:SetScript("OnDragStart", function(self) self:StartMoving() end)
    card:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    card:Hide()

    card.title = NewText(card, "GameFontNormalLarge")
    card.title:SetPoint("TOPLEFT", 20, -18)
    card.title:SetText(L["Settings profile"])

    card.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
    card.close:SetPoint("TOPRIGHT", -2, -2)
    card.close:SetScript("OnClick", function() card:Hide() end)

    card.tabExport = NewButton(card, L["Export"], 62, 22, function() UI:OpenProfile("export") end)
    card.tabExport:FitText()
    card.tabExport:SetPoint("TOPRIGHT", -34, -14)
    card.tabImport = NewButton(card, L["Import"], 62, 22, function() UI:OpenProfile("import") end)
    card.tabImport:FitText()
    card.tabImport:SetPoint("RIGHT", card.tabExport, "LEFT", -4, 0)

    local edit = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    edit:SetSize(446, 22)
    edit:SetPoint("TOPLEFT", 26, -56)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0) -- a profile with many plans is long
    edit:SetScript("OnEscapePressed", function() card:Hide() end)
    edit:SetScript("OnEnterPressed", function() UI:ProfileAction() end)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if card.mode == "export" then
            if userInput then
                self:SetText(card.exportText or "")
                self:HighlightText()
            end
        else
            UI:ValidateProfile(self:GetText())
        end
    end)
    card.edit = edit

    card.status = NewText(card, "GameFontHighlightSmall", { 0.6, 0.6, 0.6 })
    card.status:SetPoint("BOTTOMLEFT", 20, 20)
    card.status:SetWidth(360)
    card.status:SetJustifyH("LEFT")

    card.action = NewButton(card, L["Import"], 92, 24, function() UI:ProfileAction() end)
    card.action:SetPoint("BOTTOMRIGHT", -18, 14)

    table.insert(UISpecialFrames, "TalentsForgeProfile")
    self.profile = card
    return card
end

-- "1 plan", "3 plans"
function UI:PlanCount(count)
    return (count == 1 and L["%d plan"] or L["%d plans"]):format(count)
end

function UI:SetProfileStatus(text, color)
    local status = self.profile.status
    status:SetText(text or "")
    color = color or { 0.6, 0.6, 0.6 }
    status:SetTextColor(color[1], color[2], color[3])
end

function UI:OpenProfile(mode)
    local card = self.profile or self:BuildProfile()
    card.mode = mode == "import" and "import" or "export"
    card.exportText = nil
    card.valid = nil
    card:Show()
    card.tabExport:SetActive(card.mode == "export")
    card.tabImport:SetActive(card.mode == "import")
    card.action:SetShown(card.mode == "import")
    card.edit:SetText("")
    if card.mode == "export" then
        local text, plans = TP:ExportProfile()
        if text then
            card.exportText = text
            card.edit:SetText(text)
            card.edit:SetFocus()
            card.edit:HighlightText()
            self:SetProfileStatus(L["Press Ctrl+C to copy. Includes settings, positions and %s."]:format(self:PlanCount(plans)), PLAN)
        else
            self:SetProfileStatus(TP:ErrorText(plans), RED)
        end
    else
        card.edit:SetFocus()
        self:SetProfileStatus(L["Paste a profile string. It replaces your settings and adds its plans."])
    end
end

function UI:ValidateProfile(text)
    local card = self.profile
    card.valid = nil
    if TP.Trim(text) == "" then
        self:SetProfileStatus(L["Paste a profile string. It replaces your settings and adds its plans."])
        return
    end
    local profile, err = TP:DecodeProfile(text)
    if not profile then
        self:SetProfileStatus(TP:ErrorText(err), RED)
        return
    end
    card.valid = true
    local plans = 0
    for _, list in pairs(profile.plans) do
        plans = plans + #list
    end
    self:SetProfileStatus(L["Valid profile with %s."]:format(self:PlanCount(plans)), PLAN)
end

function UI:ProfileAction()
    local card = self.profile
    if not card or not card:IsShown() or card.mode ~= "import" then
        return
    end
    if not card.valid then
        self:SetProfileStatus(L["Paste a valid profile string first."], RED)
        return
    end
    local result, err = TP:ImportProfile(card.edit:GetText())
    if not result then
        self:SetProfileStatus(TP:ErrorText(err), RED)
        return
    end
    card:Hide()
    if result.skipped > 0 then
        TP:Print(L["Profile imported: settings and positions restored, %s added, %d already there."]:format(self:PlanCount(result.added), result.skipped))
    else
        TP:Print(L["Profile imported: settings and positions restored, %s added."]:format(self:PlanCount(result.added)))
    end
end

------------------------------------------------------------------------------------------------------------------------
-- Attaching to the talent window
------------------------------------------------------------------------------------------------------------------------

function UI:Build(tf)
    if self.tf == tf then
        return
    end
    if self.tf then
        return -- already attached to another talent frame; leave it alone
    end
    self.tf = tf

    self:BuildChip(tf)
    self:BuildBar(tf)
    self:BuildMenu(tf)
    self:BuildViewer(tf)
    self:BuildSheet(tf)

    tf:HookScript("OnShow", function()
        TP:ForgetMeta()
        TP.view = nil
        if TP.host and not TP.browse then
            local entry = TP.host.wanted or TP:OwnClass()
            TP.host.wanted = nil
            if entry then
                UI:OpenViewer(entry)
                return
            end
        end
        UI:Refresh()
    end)
    tf:HookScript("OnHide", function()
        UI:CloseMenu()
        UI:CloseSheet()
        UI:CloseViewer()
    end)

    -- The window redraws its buttons on its own schedule, so poll gently while it is open.
    local ticker = CreateFrame("Frame", nil, tf)
    local elapsed = 0
    ticker:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.25 then
            elapsed = 0
            UI:Refresh()
        end
    end)
end

function UI:TryAttach()
    if not TP.db then
        return false
    end
    if TP.host then
        -- Built on our own window earlier this session; the game's window only gets us after a reload.
        if TP:TalentsUnlocked() and _G.PlayerSpellsFrame and not self.reloadNoted then
            self.reloadNoted = true
            TP:Print(L["Your talents are unlocked now. Type /reload to use Talents Forge inside the talent window."])
        end
        return false
    end
    if not TP:TalentsUnlocked() then
        return false -- the window has nothing to draw on yet; /tforge browse opens one of our own
    end
    local tf = TP:GetTalentFrame()
    if not tf then
        return false
    end
    self:Build(tf)
    if tf:IsShown() then
        self:Refresh()
    end
    return true
end

-- Our own window for the class browser, used while the game's talent window is locked. It answers the few calls the rest
-- of the addon makes of a talent window.
function UI:BuildHost()
    local host = NewPanel(UIParent, 0.97)
    _G.TalentsForgeBrowser = host
    host:SetFrameStrata("HIGH")
    host:SetClampedToScreen(true)
    host:SetMovable(true)
    host:EnableMouse(true)
    function host:Place()
        local saved = TP.db.pos.host
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "CENTER", saved and saved[1] or 0, saved and saved[2] or 20)
    end
    host:Place()
    host:Hide()

    local width = math.min(1000, (UIParent:GetWidth() or 1200) - 80)
    local height = math.min(640, (UIParent:GetHeight() or 800) - 80)
    local game = _G.PlayerSpellsFrame and _G.PlayerSpellsFrame.TalentsFrame
    if game and game.GetWidth and (game:GetWidth() or 0) > 400 and (game:GetHeight() or 0) > 300 then
        width, height = game:GetWidth(), game:GetHeight()
    end
    host:SetSize(width, height)

    function host:GetTalentTreeID()
        local own = TP:OwnClass()
        return own and own.tree
    end
    function host:IsInspecting()
        return false
    end
    function host:EnumerateAllTalentButtons()
        return function() end -- there are no game buttons to put rings on
    end

    table.insert(UISpecialFrames, "TalentsForgeBrowser")
    TP.host = host
    self:Build(host)
    self.viewer.back:SetText(L["Close"])
    self.viewer.back:SetWidth(90)
    return true
end

-- Matches "mage", "Warlock" or "pal" against the class names.
local function FindClass(text)
    text = text and text:lower() or ""
    if text == "" then
        return nil
    end
    -- the English token, then the name in your language, then the start of either
    for _, entry in ipairs(TP.CLASSES) do
        if entry.token:lower() == text then
            return entry
        end
    end
    for _, entry in ipairs(TP.CLASSES) do
        if TP:ClassName(entry):lower() == text then
            return entry
        end
    end
    for _, entry in ipairs(TP.CLASSES) do
        if entry.token:lower():find(text, 1, true) == 1 or TP:ClassName(entry):lower():find(text, 1, true) == 1 then
            return entry
        end
    end
end

-- /tforge browse [class]
function UI:OpenBrowser(argument)
    local entry
    if argument and argument ~= "" then
        entry = FindClass(argument)
        if not entry then
            TP:Print(L["There's no class called \"%s\". Try /tforge browse mage."]:format(argument))
            return
        end
    end

    -- Talents unlocked: the browser lives in the game's talent window, like the menu's "Browse other classes".
    if TP:TalentsUnlocked() and not TP.host then
        local tf = TP:GetTalentFrame()
        if not (tf and tf:IsShown()) then
            local game = _G.PlayerSpellsFrame
            if game and game:IsShown() then
                TP:Print(L["Switch to the Talents tab, then type /tforge browse again."])
                return
            end
            if type(_G.TogglePlayerSpellsFrame) == "function" then
                TogglePlayerSpellsFrame()
            end
            self:TryAttach()
        end
        if not (self.tf and self.tf:IsShown()) then
            TP:Print(L["Open your talent window (default key N) on the Talents tab, then type /tforge browse again."])
            return
        end
        if entry then
            self:OpenViewer(entry)
        else
            self:OpenMenu("classes")
        end
        return
    end

    -- Locked: a window of our own.
    entry = entry or TP:OwnClass()
    if not entry then
        TP:Print(L["Couldn't tell which class you are. Try /tforge browse mage."])
        return
    end
    if not TP.host then
        self:BuildHost()
    end
    local host = TP.host
    self.viewer.empty:SetText(L["The game has no talent data for this character yet."])
    if host:IsShown() then
        self:OpenViewer(entry)
    else
        host.wanted = entry
        host:Show() -- OnShow opens the browser on that class
    end
    if not self.snap then
        TP:Print(L["The game gave no talent data for this character, so there is nothing to show yet."])
    end
end

function UI:Install()
    if self.installed then
        return
    end
    self.installed = true

    if type(_G.PlayerSpellsFrame_LoadUI) == "function" then
        hooksecurefunc("PlayerSpellsFrame_LoadUI", function() UI:TryAttach() end)
    end
    if type(_G.TogglePlayerSpellsFrame) == "function" then
        hooksecurefunc("TogglePlayerSpellsFrame", function() UI:TryAttach() end)
    end
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("PlayerSpellsFrame.OpenFrame", function() UI:TryAttach() end, TP)
    end
end
