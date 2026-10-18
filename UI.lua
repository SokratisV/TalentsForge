-- Talents Forge UI: everything is drawn inside the game's own talent window, in the game's own style.
--   chip    a small pill at the top of the window. Click it for plans, modes, import and export.
--   rings   a ring and a level badge on each talent button (the overlay)
--   bar     the level slider and buttons, only in edit mode
--   sheet   the import / export / name dialog, dimming the tree
--   viewer  another class's tree, laid out as three panels like the game's own
-- Look: Blizzard's panel buttons, close button and input box, the game's font objects, and the bronze border FlareUI uses.
local ADDON, TP = ...
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
local BASE = { 0.045, 0.04, 0.035 } -- the near-black behind a spec background

local AVAILABLE_GLOW = "talents-node-square-greenglow"

local MODES = { { "off", "Off" }, { "guide", "Guide" }, { "edit", "Edit" } }
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
        GameTooltip:AddLine("Click for plans, modes, import and export.", 1, 1, 1, true)
        GameTooltip:AddLine("Shift-drag to move.", 0.6, 0.6, 0.6, true)
        GameTooltip:Show()
    end)
    chip:SetScript("OnLeave", GameTooltip_Hide)

    MakeMovable(chip, "chip", tf, { "TOP", tf, "TOP", 0, -10 })
    chip.onMoved = function()
        if UI.bar then
            UI.bar:Place()
        end
    end
    self.chip = chip
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
        GameTooltip:AddLine("Shift-drag to move.", 1, 1, 1, true)
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
    bar.levelValue:SetWidth(36)
    bar.levelValue:SetJustifyH("LEFT")
    local secondRule = Rule(bar.levelValue, 4)

    bar.import = NewButton(bar, "Import", 52, 22, function() UI:OpenSheet("import") end)
    bar.import:SetPoint("LEFT", secondRule, "RIGHT", 8, 0)
    bar.export = NewButton(bar, "Export", 52, 22, function() UI:OpenSheet("export") end)
    bar.export:SetPoint("LEFT", bar.import, "RIGHT", 4, 0)
    bar.clear = NewButton(bar, "Clear", 48, 22, function(self)
        if not self.confirm then
            self.confirm = true
            self:SetText("Sure?")
            C_Timer.After(2, function()
                self.confirm = nil
                self:SetText("Clear")
            end)
            return
        end
        self.confirm = nil
        self:SetText("Clear")
        local snap = UI.snap
        if snap and snap.plan then
            snap.plan.order = {}
            TP.view = nil
            UI:Refresh()
        end
    end)
    bar.clear:SetPoint("LEFT", bar.export, "RIGHT", 4, 0)

    -- right under the chip, wherever the chip is
    MakeMovable(bar, "bar", tf, { "TOP", self.chip, "BOTTOM", 0, -4 })
    self.bar = bar
end

function UI:BuildOverlay(button)
    local overlay = CreateFrame("Button", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(button:GetFrameLevel() + 15)
    overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    overlay.button = button

    overlay.ring = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    overlay.ring:SetPoint("TOPLEFT", -3, 3)
    overlay.ring:SetPoint("BOTTOMRIGHT", 3, -3)
    overlay.ring:SetBackdrop({ edgeFile = WHITE, edgeSize = 2 })
    overlay.ring:Hide()

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

    overlay:SetScript("OnClick", function(self, mouseButton)
        UI:NodeClicked(self.nodeID, mouseButton)
    end)
    overlay:SetScript("OnEnter", function(self)
        local original = self.button:GetScript("OnEnter")
        if original then
            original(self.button)
        end
        if TP:Mode() == "edit" then
            if not original then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            end
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Talents Forge", PLAN[1], PLAN[2], PLAN[3])
            GameTooltip:AddLine("Left-click: plan a point", 1, 1, 1)
            GameTooltip:AddLine("Shift-click: plan every rank", 1, 1, 1)
            GameTooltip:AddLine("Right-click: remove a point", 1, 1, 1)
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

    -- Off on the left edge, Edit on the right edge, Guide centred: equal margins either side.
    menu.modes = {}
    for index, mode in ipairs(MODES) do
        local key = mode[1]
        local button = NewButton(menu, mode[2], 70, 22, function()
            TP:SetMode(key)
            UI:CloseMenu()
        end)
        if index == 1 then
            button:SetPoint("TOPLEFT", 10, -10)
        elseif index == #MODES then
            button:SetPoint("TOPRIGHT", -10, -10)
        else
            button:SetPoint("TOP", 0, -10)
        end
        menu.modes[key] = button
    end

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
    row.delete = NewLink(row, "Delete", RED)
    row.delete:SetPoint("RIGHT", -8, 0)
    row.rename = NewLink(row, "Rename", GOLD)
    row.rename:SetPoint("RIGHT", row.delete, "LEFT", -6, 0)
    row.delete:Hide()
    row.rename:Hide()
    row:SetScript("OnEnter", function(self) self.hover:Show() end)
    row:SetScript("OnLeave", function(self) self.hover:Hide() end)
    menu.rows[index] = row
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
    if self.menu then
        self.menu.catcher:Hide()
    end
end

function UI:OpenMenu(page)
    local snap = self.snap
    if not snap then
        return
    end
    local menu = self.menu
    local treeID = snap.treeID
    local browsing = TP.browse ~= nil

    for _, row in ipairs(menu.rows) do
        row:Hide()
    end
    for _, rule in ipairs(menu.rules) do
        rule:Hide()
    end
    for key, button in pairs(menu.modes) do
        button:SetShown(not browsing and page ~= "classes")
        button:SetActive(TP.db.mode == key)
    end

    local y = (browsing or page == "classes") and -10 or -40
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

    local function Finish()
        menu:SetHeight(-y + 10)
        menu:ClearAllPoints()
        menu:SetPoint("TOP", self.chip, "BOTTOM", 0, -4)
        menu.catcher:Show()
    end

    if page == "classes" then
        Row("< Back", nil, function() UI:OpenMenu() end, { 0.6, 0.6, 0.6 })
        Rule()
        for _, entry in ipairs(TP.CLASSES) do
            local own = entry.tree == TP.ownTreeID
            local viewing = (TP.browse == entry.tree) or (own and not browsing)
            local classColor = RAID_CLASS_COLORS and RAID_CLASS_COLORS[entry.token]
            Row((viewing and "> " or "   ") .. TP:ClassName(entry), own and "you" or nil, function()
                UI:CloseMenu()
                if own then
                    UI:CloseViewer()
                else
                    UI:OpenViewer(entry)
                end
            end, classColor and { classColor.r, classColor.g, classColor.b } or nil)
        end
        Finish()
        return
    end

    if browsing then
        Row("< Back to my talents", nil, function()
            UI:CloseMenu()
            UI:CloseViewer()
        end, { 0.6, 0.6, 0.6 })
    end
    Rule()
    local plans = TP:Plans(treeID)
    if #plans == 0 then
        Row("No plans yet", nil, function() end, { 0.6, 0.6, 0.6 })
    end
    for _, plan in ipairs(plans) do
        local selected = snap.plan == plan
        local row
        row = Row((selected and "> " or "   ") .. plan.name, #plan.order .. "/" .. TP.POINT_CAP, function()
            TP:SetActive(treeID, plan)
            UI:CloseMenu()
            UI:Refresh()
        end, selected and PLAN or nil, {
            rename = function()
                TP:SetActive(treeID, plan)
                UI:CloseMenu()
                UI:Refresh()
                UI:OpenSheet("rename")
            end,
            delete = function()
                local link = row.delete
                if not link.confirm then
                    -- the first click only asks
                    link.confirm = true
                    link.text:SetText("Sure?")
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
    Row("+ New plan", nil, function()
        UI:CloseMenu()
        UI:OpenSheet("new")
    end, GOLD)

    Rule()
    Row("Import build...", nil, function()
        UI:CloseMenu()
        UI:OpenSheet("import")
    end)
    if snap.plan then
        Row("Export build...", nil, function()
            UI:CloseMenu()
            UI:OpenSheet("export")
        end)
    end
    Rule()
    Row("Browse other classes...", nil, function() UI:OpenMenu("classes") end, GOLD)
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
    card:SetSize(450, 142)
    card:SetPoint("CENTER")
    card:EnableMouse(true)
    sheet.card = card

    sheet.title = NewText(card, "GameFontNormalLarge")
    sheet.title:SetPoint("TOPLEFT", 20, -18)

    sheet.close = CreateFrame("Button", nil, card, "UIPanelCloseButton")
    sheet.close:SetPoint("TOPRIGHT", -2, -2)
    sheet.close:SetScript("OnClick", function() UI:CloseSheet() end)

    sheet.tabExport = NewButton(card, "Export", 62, 22, function() UI:OpenSheet("export") end)
    sheet.tabExport:SetPoint("TOPRIGHT", -34, -14)
    sheet.tabImport = NewButton(card, "Import", 62, 22, function() UI:OpenSheet("import") end)
    sheet.tabImport:SetPoint("RIGHT", sheet.tabExport, "LEFT", -4, 0)

    local edit = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    edit:SetSize(396, 22)
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
    sheet.status:SetWidth(310)
    sheet.status:SetJustifyH("LEFT")

    sheet.action = NewButton(card, "OK", 92, 24, function() UI:SheetAction() end)
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

    sheet.mode = mode
    sheet.parsed = nil
    sheet.exportText = nil
    sheet:Show()

    local sharing = mode == "import" or mode == "export"
    sheet.tabExport:SetShown(sharing)
    sheet.tabImport:SetShown(sharing)
    sheet.tabExport:SetActive(mode == "export")
    sheet.tabImport:SetActive(mode == "import")
    sheet.action:SetShown(mode ~= "export")
    sheet.edit:SetText("")

    if mode == "export" then
        sheet.title:SetText("Share build")
        local text, err = TP:Export(snap.plan, snap.meta, self:ClassIDFor(snap.treeID))
        if text then
            sheet.exportText = text
            sheet.edit:SetText(text)
            sheet.edit:SetFocus()
            sheet.edit:HighlightText()
            self:SetStatus("Press Ctrl+C to copy. " .. #snap.plan.order .. " points.", PLAN)
        else
            self:SetStatus(TP:ErrorText(err), RED)
        end
    elseif mode == "import" then
        sheet.title:SetText("Share build")
        sheet.action:SetText("Import")
        sheet.edit:SetFocus()
        self:SetStatus("Paste a build string.")
    elseif mode == "new" then
        sheet.title:SetText("New plan")
        sheet.action:SetText("Create")
        sheet.edit:SetText(TP:UniqueName(snap.treeID, "Plan"))
        sheet.edit:SetFocus()
        sheet.edit:HighlightText()
        self:SetStatus("Name your plan.")
    elseif mode == "rename" then
        sheet.title:SetText("Rename plan")
        sheet.action:SetText("Rename")
        sheet.edit:SetText(snap.plan and snap.plan.name or "")
        sheet.edit:SetFocus()
        sheet.edit:HighlightText()
        self:SetStatus("Name your plan.")
    end
end

function UI:CloseSheet()
    local sheet = self.sheet
    if sheet then
        sheet.edit:ClearFocus()
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
        self:SetStatus("Paste a build string.")
        return
    end
    local order, err, extra = TP:Decode(text, snap.meta, self:ClassIDFor(snap.treeID))
    if not order then
        local other = err == "class" and TP:ClassByID(extra)
        if other then
            -- A build for another class: the Import button opens that class's tree, then the string checks out.
            sheet.pendingClass = other
            self:SetStatus("This build is for " .. TP:ClassName(other) .. ". Import opens their tree.", GOLD)
        else
            self:SetStatus(TP:ErrorText(err, extra), RED)
        end
        return
    end
    sheet.parsed = order
    local split = TP:Split(snap.meta, order)
    self:SetStatus("Valid build. " .. table.concat(split, " / ") .. ", " .. #order .. " points.", PLAN)
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
            if entry.tree == TP.ownTreeID then
                self:CloseViewer()
            else
                self:OpenViewer(entry)
            end
            self:OpenSheet("import")
            sheet.edit:SetText(text)
            return
        end
        if not sheet.parsed then
            self:SetStatus("Paste a valid build string first.", RED)
            return
        end
        local plan = TP:NewPlan(snap.treeID, "Imported", sheet.parsed)
        if not TP.browse and TP.db.mode == "off" then
            TP.db.mode = "guide"
        end
        TP:Print("Imported \"" .. plan.name .. "\" (" .. #plan.order .. " points).")
    elseif sheet.mode == "new" then
        local plan = TP:NewPlan(snap.treeID, sheet.edit:GetText())
        if not TP.browse and TP.db.mode == "off" then
            TP.db.mode = "edit"
        end
        TP:Print("Created \"" .. plan.name .. "\".")
    elseif sheet.mode == "rename" and snap.plan then
        local ok, message = TP:RenamePlan(snap.treeID, snap.plan, sheet.edit:GetText())
        if not ok then
            self:SetStatus(message or "Enter a name.", RED)
            return
        end
    else
        return
    end
    self:CloseSheet()
    self:Refresh()
end

------------------------------------------------------------------------------------------------------------------------
-- Clicking talents in edit mode
------------------------------------------------------------------------------------------------------------------------

function UI:NodeClicked(nodeID, mouseButton)
    if TP:Mode() ~= "edit" or not nodeID then
        return
    end
    local snap = TP:Snapshot()
    if not snap then
        return
    end
    if not snap.plan then
        TP:NewPlan(snap.treeID, "Plan")
        snap = TP:Snapshot()
        if not snap then
            return
        end
    end

    if mouseButton == "RightButton" then
        local ok, reason = TP:RemovePoint(snap, nodeID)
        if not ok then
            TP:Error(TP:ErrorText(reason))
        end
    else
        local node = snap.meta.nodes[nodeID]
        local times = IsShiftKeyDown() and node and node.max or 1
        for attempt = 1, times do
            local ok, reason = TP:AddPoint(snap, nodeID)
            if not ok then
                if attempt == 1 or not IsShiftKeyDown() then
                    TP:Error(TP:ErrorText(reason))
                end
                break
            end
        end
    end
    self:Refresh()
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
        text = "Talents Forge: no plan yet"
    elseif mode == "edit" then
        local browsed = TP.browse and TP:ClassByTree(TP.browse)
        local prefix = browsed and (TP:ClassName(browsed) .. ":  ") or "Editing  "
        text = prefix .. Truncate(plan.name, 18) .. "  " .. #plan.order .. "/" .. TP.POINT_CAP
    elseif mode == "guide" then
        if snap.nextNode then
            text = "Next: " .. TP:NodeName(snap.meta, snap.nextNode) .. "  (level " .. TP:LevelOf(snap.nextIndex) .. ")"
        elseif #plan.order == 0 then
            text = Truncate(plan.name, 18) .. " is empty"
        else
            text = Truncate(plan.name, 18) .. " complete"
        end
    else
        text = Truncate(plan.name, 24)
    end

    chip.text:SetText(text)
    chip:SetWidth(math.max(120, chip.text:GetStringWidth() + 58))

    local active = mode ~= "off" and plan ~= nil
    local color = active and PLAN or BRONZE
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
    bar.levelValue:SetText(#order == 0 and "-" or ("Lv " .. TP:LevelOf(count)))
end

-- frame: the game's talent window, or the class browser. snap is nil to clear the frame's overlays.
function UI:RefreshOverlays(frame, snap, mode)
    local tf = frame
    if not tf or not tf.EnumerateAllTalentButtons then
        return
    end

    local editing = snap and mode == "edit" and snap.plan ~= nil
    local guiding = snap and mode == "guide" and snap.plan ~= nil and snap.nextNode ~= nil
    local stats, states
    if editing then
        local count = math.min(TP.view or #snap.plan.order, #snap.plan.order)
        stats = PlanStats(snap, count)
        states = TP:NodeStates(snap.meta, snap.plan.order, count) -- what could be taken after those points
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
            end
        else
            overlay = overlay or self:BuildOverlay(button)
            overlay.nodeID = nodeID
            overlay:Show()
            overlay:EnableMouse(editing)

            local ring, badge, glow = overlay.ring, overlay.badge, overlay.glow
            local show = false
            local isNext = false

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
            if isNext then
                if not overlay.pulse:IsPlaying() then
                    overlay.pulse:Play()
                end
            else
                overlay.pulse:Stop()
                ring:SetAlpha(1)
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
    viewer.note:SetText("Planning only. Your own talents aren't touched.")

    viewer.back = NewButton(viewer, "Back to my talents", 140, 24, function()
        UI:CloseViewer()
    end)
    viewer.back:SetPoint("TOPRIGHT", -22, -14)

    viewer.empty = NewText(viewer, "GameFontNormal", RED)
    viewer.empty:SetPoint("CENTER")
    viewer.empty:SetText("The game didn't describe this class's talents.")
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
            GameTooltip:AddLine("Max rank " .. node.max, 0.6, 0.6, 0.6)
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
        panel.title:SetText(entry and entry.specs[index] or "")
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
    if entry.tree == TP.ownTreeID then
        self:CloseViewer()
        return
    end

    TP.browse = entry.tree
    TP.view = nil
    self:CloseMenu()
    self.viewer.meta = nil -- lay it out afresh for this class
    self.viewer:Show()

    local snap = TP:Snapshot()
    if snap and not snap.plan then
        TP:NewPlan(snap.treeID, "Plan")
    end
    self:Refresh()
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
    self:CloseMenu()
    self:CloseSheet()
    if wasBrowsing then
        self:Refresh()
    end
end

function UI:ResetPositions()
    if self.chip then
        self.chip:Place()
        self.bar:Place()
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
