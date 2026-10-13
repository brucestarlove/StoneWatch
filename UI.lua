local _, ns = ...
local UI = {}
ns.UI = UI
local colors = {given = {0.52, 0.87, 0.64}, used = {1, 0.3, 0.25}, quiet = {0.55, 0.6, 0.56}}

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

-- The hover tooltip and the pinned list show the same players; the pinned
-- list adds recent uses in place of the click hints.
function UI:Fill(tooltip, pinned)
    local quiet = colors.quiet
    tooltip:AddLine("StoneWatch", 0.5, 0.87, 0.63)
    local entries = sortedEntries()
    for _, entry in ipairs(entries) do
        tooltip:AddDoubleLine(entry.name, entry.state == "used" and "Used" or "Given", 0.9, 0.9, 0.9, unpack(colors[entry.state]))
    end
    if #entries == 0 then tooltip:AddLine("Trade a healthstone to start tracking.", unpack(quiet)) end
    local ready, reason = ns.Tracking:MeterStatus()
    if not ready then
        tooltip:AddLine(reason, 1, 0.55, 0.3, true)
    elseif ns.pendingScan then
        tooltip:AddLine(ns.scanReason or "Waiting for healing data.", quiet[1], quiet[2], quiet[3], true)
    end
    if not pinned then
        tooltip:AddLine("Left-click: keep open", unpack(quiet))
        tooltip:AddLine("Right-click: options", unpack(quiet))
    elseif #ns.db.history > 0 then
        tooltip:AddLine(" ")
        tooltip:AddLine("Recent uses", unpack(quiet))
        for i = 1, math.min(5, #ns.db.history) do
            local event = ns.db.history[i]
            tooltip:AddDoubleLine(event.name, date("%H:%M", event.at), 0.9, 0.9, 0.9, unpack(quiet))
        end
    end
    tooltip:Show()
end

function UI:Tooltip()
    if self.panel:IsShown() then return end
    GameTooltip:SetOwner(self.badge, "ANCHOR_NONE")
    GameTooltip:SetPoint("TOP", self.badge, "BOTTOM", 0, -4)
    self:Fill(GameTooltip)
end

function UI:Create()
    local badge = CreateFrame("Button", "StoneWatchBadge", UIParent)
    badge:SetSize(174, 26)
    badge:SetFrameStrata("MEDIUM")
    badge:SetClampedToScreen(true)
    badge:SetMovable(true)
    badge:RegisterForClicks("LeftButtonUp", "RightButtonUp")
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
    badge:SetScript("OnEnter", function() self:Tooltip() end)
    badge:SetScript("OnLeave", function() GameTooltip:Hide() end)
    badge:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then ns.Options:Open() else self:Toggle() end
    end)
    badge:SetScript("OnDragStart", function() if not ns.db.options.locked then badge:StartMoving() end end)
    badge:SetScript("OnDragStop", function()
        badge:StopMovingOrSizing()
        local point, _, relativePoint, x, y = badge:GetPoint()
        ns.db.position = {point = point, relativePoint = relativePoint, x = x, y = y}
    end)
    self.badge = badge

    -- A tooltip of its own, so the pinned list looks and sizes itself like the hover one.
    local panel = CreateFrame("GameTooltip", "StoneWatchPanel", UIParent, "GameTooltipTemplate")
    panel:SetFrameStrata("MEDIUM")
    panel:Hide()
    self.panel = panel
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
    self.panel:ClearLines()
    self:Fill(self.panel, true)
end

function UI:Toggle()
    if self.panel:IsShown() then self.panel:Hide(); return end
    if GameTooltip:IsOwned(self.badge) then GameTooltip:Hide() end
    self.panel:SetOwner(UIParent, "ANCHOR_NONE")
    self.panel:SetPoint("TOP", self.badge, "BOTTOM", 0, -4)
    self:Fill(self.panel, true)
end

function UI:ResetPosition()
    ns.db.position = nil
    self.badge:StopMovingOrSizing()
    self.badge:ClearAllPoints()
    self.badge:SetPoint("TOP", UIParent, "TOP", 0, -110)
    ns.Refresh()
end
