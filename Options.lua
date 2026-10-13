local _, ns = ...
local Options = {checks = {}}
ns.Options = Options

local function text(parent, value, x, y, font, width)
    local label = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    if width then label:SetWidth(width) end
    label:SetText(value)
    return label
end

local function tooltip(control, title, description)
    control:SetScript("OnEnter", function()
        GameTooltip:SetOwner(control, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        GameTooltip:AddLine(description, 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    control:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function Options:Create()
    local panel = CreateFrame("Frame", "StoneWatchOptionsPanel", UIParent)
    panel:Hide()
    self.panel = panel
    text(panel, "StoneWatch " .. ns.VERSION, 16, -16, "GameFontNormalLarge")
    text(panel, "Healthstone trades and group usage after combat. Settings are saved for this character.", 16, -47, nil, 540)
    text(panel, "Display", 16, -98, "GameFontNormal")
    text(panel, "Notifications", 316, -98, "GameFontNormal")
    local toggles = {
        {"icons", "Show unit frame icons", 16, -122, "Show healthstone indicators on Blizzard's target, focus, party, and raid frames. Your own character has no icon."},
        {"badge", "Show HUD", 16, -150, "Show Given and Used counts for current group members, including refills automatically shared by other StoneWatch users."},
        {"locked", "Lock HUD position", 16, -178, "Turn this off to drag the HUD with the left mouse button."},
        {"minimap", "Show minimap button", 16, -206, "Left-click the button for tracked players; right-click for options. Drag it around the minimap to move it."},
        {"sound", "Play a sound", 316, -122, "Play one sound after combat when one or more tracked players use a healthstone."},
        {"chat", "Show a local chat notice", 316, -150, "Print the names of players who used a healthstone after combat. Only you see this notice."},
    }
    for _, option in ipairs(toggles) do
        local key = option[1]
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetSize(22, 22)
        check:SetPoint("TOPLEFT", option[3], option[4])
        check.Text:SetText(option[2])
        check:SetScript("OnClick", function()
            ns.db.options[key] = check:GetChecked() and true or false
            ns.Refresh()
        end)
        tooltip(check, option[2], option[5])
        self.checks[key] = check
    end

    self.sizeLabel = text(panel, "", 316, -205, "GameFontNormal")
    local slider = CreateFrame("Slider", "StoneWatchIconSizeSlider", panel, "MinimalSliderTemplate")
    slider:SetSize(220, 19)
    slider:SetPoint("TOPLEFT", 316, -233)
    slider:SetMinMaxValues(10, 24)
    slider:SetValueStep(1)
    slider:SetScript("OnValueChanged", function(_, value)
        if self.refreshing then return end
        local size = math.max(10, math.min(24, math.floor(value + 0.5)))
        if ns.db.options.iconSize ~= size then
            ns.Frames:SetSize(size)
            ns.Refresh()
        end
    end)
    tooltip(slider, "Unit frame icon size", "Choose 10 to 24 pixels. Size changes made in combat apply when combat ends.")
    text(panel, "10 px", 316, -257)
    text(panel, "24 px", 509, -257)
    self.slider = slider

    text(panel, "Actions", 16, -305, "GameFontNormal")
    local actions = {
        {"Tracked players", function() HideUIPanel(SettingsPanel); ns.UI:Toggle() end, "Open the list of supplied players and recent healthstone uses."},
        {"Scan healing data", function() ns.Tracking:CancelScan(); ns.Tracking:RequestScan(0); ns.Print("Checking healing data after combat.") end, "Check readable damage meter data again. Scanning waits until the group leaves combat."},
        {"Reset HUD position", function() ns.UI:ResetPosition() end, "Restore the HUD to the top center of the screen. This is also available as /sw reset."},
        {"Clear trades & history", function() ns.model:Clear(); ns.Sync:ClearQueues(); ns.Refresh(); ns.Print("Local tracked trades and recent uses cleared.") end, "Clear local trades and recent uses without changing settings. Shared records can appear again when other StoneWatch users report their state."},
        {"Restore defaults", function() self:RestoreDefaults() end, "Restore display and notification settings, HUD position, and minimap button position. Tracked trades and history are kept."},
        {"Show status", function() ns.Print(ns.Tracking:Diagnostic()) end, "Print the detected data source and tracking status to your local chat."},
    }
    for i, action in ipairs(actions) do
        local button = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        button:SetSize(168, 24)
        button:SetPoint("TOPLEFT", 16 + ((i - 1) % 3) * 184, -332 - math.floor((i - 1) / 3) * 36)
        button:SetText(action[1])
        button:SetScript("OnClick", action[2])
        tooltip(button, action[1], action[3])
    end
    text(panel, "Given and Used count current group members you or other StoneWatch users supplied. Refills sync automatically; recipients do not need the addon.", 16, -417, nil, 540)
    text(panel, "Uses need recorded healing and appear after combat. Details is selected automatically when compatible; otherwise Blizzard's meter is used.", 16, -466, nil, 540)
    text(panel, ns.CREDIT, 16, -521, "GameFontNormalSmall", 540)
    panel:SetScript("OnShow", function() self:Refresh() end)
    panel.OnRefresh = function() self:Refresh() end
    panel.OnDefault = function() self:RestoreDefaults() end
    self.category = Settings.RegisterCanvasLayoutCategory(panel, "StoneWatch")
    Settings.RegisterAddOnCategory(self.category)
end

function Options:Open()
    ns.UI.panel:Hide()
    Settings.OpenToCategory(self.category:GetID())
end

function Options:Refresh()
    if not self.panel or not self.panel:IsShown() then return end
    self.refreshing = true
    for key, check in pairs(self.checks) do check:SetChecked(ns.db.options[key]) end
    self.slider:SetValue(ns.db.options.iconSize)
    self.sizeLabel:SetText("Icon size: " .. ns.db.options.iconSize .. " px")
    self.refreshing = false
end

function Options:RestoreDefaults()
    for key, value in pairs(ns.defaults) do ns.db.options[key] = value end
    ns.db.minimapAngle = 225
    ns.Frames:SetSize(ns.db.options.iconSize)
    ns.Minimap:Position()
    ns.UI:ResetPosition()
end
