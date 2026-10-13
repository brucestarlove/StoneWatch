local _, ns = ...
local UI = {}
ns.UI = UI
local colors = {given = {0.52, 0.87, 0.64}, used = {1, 0.3, 0.25}}

local function backdrop(frame)
    local texture = frame:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetColorTexture(0.055, 0.07, 0.065, 0.94)
end

local function sortedEntries()
    local entries = {}
    for guid in pairs(ns.roster) do
        local entry = ns.db.records[guid]
        if entry then entries[#entries + 1] = entry end
    end
    table.sort(entries, function(a, b)
        if a.state ~= b.state then return a.state == "used" end
        return a.name < b.name
    end)
    return entries
end

function UI:Tooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
    GameTooltip:AddLine("StoneWatch", 0.5, 0.87, 0.63)
    GameTooltip:AddLine("Counts include your trades and refills shared by StoneWatch users.", 0.75, 0.78, 0.75, true)
    GameTooltip:AddLine("Given: no use detected since the latest refill. Used: a use was recorded.", 0.75, 0.78, 0.75, true)
    GameTooltip:AddLine("Refills from players without StoneWatch remain unknown.", 0.75, 0.78, 0.75, true)
    for _, entry in ipairs(sortedEntries()) do
        local color = colors[entry.state]
        GameTooltip:AddDoubleLine(entry.name, entry.state == "used" and "Used" or "Supplied", 0.9, 0.9, 0.9, unpack(color))
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Green: supplied. Desaturated with a red outline and !: used.", 0.75, 0.78, 0.75, true)
    GameTooltip:AddLine("Group status updates after combat.", 0.75, 0.78, 0.75, true)
    local ready, reason = ns.Tracking:MeterStatus()
    if not ready then
        GameTooltip:AddLine(reason, 1, 0.55, 0.3, true)
    elseif ns.pendingScan then
        GameTooltip:AddLine(ns.scanReason or "Waiting for healing data.", 1, 0.75, 0.3, true)
    end
    GameTooltip:AddLine("Click for tracked players. /sw options for settings.", 0.55, 0.6, 0.56, true)
    GameTooltip:AddLine("/sw unlock to move the HUD; /sw reset to restore its position.", 0.55, 0.6, 0.56, true)
    GameTooltip:Show()
end

function UI:Create()
    local badge = CreateFrame("Button", "StoneWatchBadge", UIParent)
    badge:SetSize(174, 26)
    badge:SetFrameStrata("MEDIUM")
    badge:SetClampedToScreen(true)
    badge:SetMovable(true)
    badge:RegisterForDrag("LeftButton")
    local position = ns.db.position or {point = "TOP", relativePoint = "TOP", x = 0, y = -110}
    badge:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
    backdrop(badge)
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 3, 0)
    icon:SetTexture(ns.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    badge.icon = icon
    badge.text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge.text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
    badge.text:SetPoint("RIGHT", -5, 0)
    badge.text:SetJustifyH("LEFT")
    badge:SetScript("OnEnter", function() self:Tooltip(badge) end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge:SetScript("OnClick", function() self:Toggle() end)
    badge:SetScript("OnDragStart", function() if not ns.db.options.locked then badge:StartMoving() end end)
    badge:SetScript("OnDragStop", function()
        badge:StopMovingOrSizing()
        local point, _, relativePoint, x, y = badge:GetPoint()
        ns.db.position = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
    self.badge = badge

    local panel = CreateFrame("Frame", "StoneWatchPanel", UIParent)
    panel:SetSize(390, 474)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("DIALOG")
    panel:SetMovable(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", panel.StartMoving)
    panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
    backdrop(panel)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -15)
    title:SetText("StoneWatch")
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT")
    close:SetScript("OnClick", function() panel:Hide() end)
    panel.subtitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    panel.subtitle:SetPoint("TOPLEFT", 16, -43)
    panel.subtitle:SetWidth(355)
    panel.subtitle:SetJustifyH("LEFT")

    local options = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    options:SetSize(78, 22)
    options:SetPoint("TOPRIGHT", -37, -13)
    options:SetText("Options")
    options:SetScript("OnClick", function() ns.Options:Open() end)
    local scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -76)
    scroll:SetPoint("BOTTOMRIGHT", -33, 52)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(334, 280)
    scroll:SetScrollChild(content)
    self.content, self.rows = content, {}
    local footer = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    footer:SetPoint("BOTTOMLEFT", 16, 13)
    footer:SetWidth(355)
    footer:SetJustifyH("LEFT")
    footer:SetText("Status updates after combat. Unknown players have no icon.\n/sw scan checks again; /sw clear clears tracked trades.")
    panel:Hide()
    self.panel = panel
    UISpecialFrames[#UISpecialFrames + 1] = "StoneWatchPanel"
end

function UI:Refresh()
    if not self.badge then return end
    local given, used = ns.model:Counts(ns.roster)
    self.badge:SetShown(ns.db.options.badge and (ns.isWarlock or given + used > 0))
    self.badge.icon:SetDesaturated(false)
    local meterEnabled = ns.Tracking:MeterStatus()
    self.badge.text:SetText("Given " .. given .. "  |  Used " .. used)
    self.badge.text:SetTextColor(unpack((used > 0 or not meterEnabled) and colors.used or colors.given))
    if not self.panel:IsShown() then return end
    self.panel.subtitle:SetText("Tracked group members: " .. given .. " given   |   " .. used .. " used")
    local entries, lines = sortedEntries(), {}
    lines[#lines + 1] = {text = "CURRENT GROUP", color = {0.5, 0.87, 0.63}}
    if #entries == 0 then lines[#lines + 1] = {text = "Trade a healthstone to start tracking a player."} end
    for _, entry in ipairs(entries) do
        lines[#lines + 1] = {text = entry.name .. "  -  " .. (entry.state == "used" and "Used" or "Supplied"), color = colors[entry.state]}
    end
    lines[#lines + 1] = {text = ""}
    lines[#lines + 1] = {text = "RECENT USES", color = {0.5, 0.87, 0.63}}
    for i = 1, math.min(10, #ns.db.history) do
        local event = ns.db.history[i]
        lines[#lines + 1] = {text = date("%H:%M", event.at) .. "  " .. event.name}
    end
    if #ns.db.history == 0 then lines[#lines + 1] = {text = "Uses will appear here after a fight."} end
    for i, line in ipairs(lines) do
        local row = self.rows[i]
        if not row then
            row = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row:SetPoint("TOPLEFT", 0, -(i - 1) * 22)
            row:SetWidth(334)
            row:SetJustifyH("LEFT")
            self.rows[i] = row
        end
        row:SetText(line.text)
        row:SetTextColor(unpack(line.color or {0.86, 0.9, 0.86}))
        row:Show()
    end
    for i = #lines + 1, #self.rows do self.rows[i]:Hide() end
    self.content:SetHeight(math.max(280, #lines * 22))
end

function UI:Toggle()
    self.panel:SetShown(not self.panel:IsShown())
    self:Refresh()
end

function UI:ResetPosition()
    ns.db.position = nil
    self.badge:StopMovingOrSizing()
    self.badge:ClearAllPoints()
    self.badge:SetPoint("TOP", UIParent, "TOP", 0, -110)
    ns.Refresh()
end
