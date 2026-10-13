local _, ns = ...
local MapButton = {}
ns.Minimap = MapButton

function MapButton:Position()
    if not self.button then return end
    local angle = math.rad(ns.db.minimapAngle)
    self.button:ClearAllPoints()
    self.button:SetPoint("CENTER", Minimap, "CENTER",
        math.cos(angle) * (Minimap:GetWidth() / 2 + 10),
        math.sin(angle) * (Minimap:GetHeight() / 2 + 10))
end

function MapButton:Create()
    if self.button or not Minimap then return end
    local button = CreateFrame("Button", "StoneWatchMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(Minimap:GetFrameLevel() + 10)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexture(ns.ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    button:SetScript("OnClick", function(_, mouseButton)
        if button.dragging or button.suppressClick then return end
        if mouseButton == "RightButton" then ns.Options:Open() else ns.UI:Toggle() end
    end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_LEFT")
        GameTooltip:AddLine("StoneWatch", 0.5, 0.87, 0.63)
        GameTooltip:AddLine("Left-click: tracked players", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Right-click: options", 0.9, 0.9, 0.9)
        GameTooltip:AddLine("Drag: move around the minimap", 0.9, 0.9, 0.9)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    button:SetScript("OnDragStart", function()
        button.dragging = true
        GameTooltip:Hide()
        button:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local centerX, centerY = Minimap:GetCenter()
            if not centerX or not centerY then return end
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX)) % 360
            self:Position()
        end)
    end)
    button:SetScript("OnDragStop", function()
        button:SetScript("OnUpdate", nil)
        button.dragging, button.suppressClick = false, true
        C_Timer.After(0, function() button.suppressClick = false end)
    end)
    button:SetScript("OnHide", function()
        button:SetScript("OnUpdate", nil)
        button.dragging = false
    end)
    Minimap:HookScript("OnSizeChanged", function() self:Position() end)
    self.button = button
    self:Position()
    self:Refresh()
end

function MapButton:Refresh()
    if self.button then self.button:SetShown(ns.db.options.minimap) end
end
