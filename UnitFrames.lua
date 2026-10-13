local _, ns = ...
local Frames = {overlays = setmetatable({}, {__mode = "k"}), pending = setmetatable({}, {__mode = "k"}), hooked = {}}
ns.Frames = Frames

-- Outside positions hang off the unit frame; inside ones sit on its health bar.
Frames.positions = {
    {key = "outsideRight", label = "Outside right", outside = true, point = "LEFT", to = "RIGHT", x = 2, y = 0},
    {key = "outsideLeft", label = "Outside left", outside = true, point = "RIGHT", to = "LEFT", x = -2, y = 0},
    {key = "outsideTop", label = "Outside top", outside = true, point = "BOTTOM", to = "TOP", x = 0, y = 2},
    {key = "outsideBottom", label = "Outside bottom", outside = true, point = "TOP", to = "BOTTOM", x = 0, y = -2},
    {key = "topLeft", label = "Inside top left", point = "TOPLEFT", to = "TOPLEFT", x = 2, y = -2},
    {key = "top", label = "Inside top", point = "TOP", to = "TOP", x = 0, y = -2},
    {key = "topRight", label = "Inside top right", point = "TOPRIGHT", to = "TOPRIGHT", x = -2, y = -2},
    {key = "left", label = "Inside left", point = "LEFT", to = "LEFT", x = 2, y = 0},
    {key = "center", label = "Inside center", point = "CENTER", to = "CENTER", x = 0, y = 0},
    {key = "right", label = "Inside right", point = "RIGHT", to = "RIGHT", x = -2, y = 0},
    {key = "bottomLeft", label = "Inside bottom left", point = "BOTTOMLEFT", to = "BOTTOMLEFT", x = 2, y = 2},
    {key = "bottom", label = "Inside bottom", point = "BOTTOM", to = "BOTTOM", x = 0, y = 2},
    {key = "bottomRight", label = "Inside bottom right", point = "BOTTOMRIGHT", to = "BOTTOMRIGHT", x = -2, y = 2},
}
for _, position in ipairs(Frames.positions) do Frames.positions[position.key] = position end

local function layoutFor(unit)
    return ns.Readable(unit) and type(unit) == "string" and unit:find("^raid") and "raid" or "party"
end

function Frames:Place(source, icon, layout)
    local options = ns.db.options
    local position = self.positions[options[layout .. "Position"]]
    icon:ClearAllPoints()
    icon:SetPoint(position.point, position.outside and source or icon.bar, position.to,
        position.x + options[layout .. "X"], position.y + options[layout .. "Y"])
    icon.layout = layout
end

function Frames:Relayout()
    for _, icon in pairs(self.overlays) do icon.layout = nil end
end

function Frames:Add(source)
    if not source or not ns.Readable(source) or not source.GetObjectType then return end
    if source.IsForbidden and source:IsForbidden() then return end
    if self.overlays[source] then self.pending[source] = nil; return end
    if InCombatLockdown() then self.pending[source] = true; return end
    local icon = CreateFrame("Frame", nil, UIParent)
    icon:SetSize(ns.db.options.iconSize, ns.db.options.iconSize)
    icon:SetFrameStrata("MEDIUM")
    icon:SetFrameLevel(source:GetFrameLevel() + 10)
    icon:EnableMouse(false)
    local anchor = source.healthbar or source.healthBar
    if not anchor and source.HealthBarContainer then anchor = source.HealthBarContainer.HealthBar end
    icon.bar = anchor or source
    self:Place(source, icon, layoutFor(source.unit))
    icon.background = icon:CreateTexture(nil, "BACKGROUND")
    icon.background:SetAllPoints()
    icon.background:SetColorTexture(0.02, 0.025, 0.02, 0.95)
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 1, -1)
    icon.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    icon.texture:SetTexture(ns.ICON)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.outline = icon:CreateTexture(nil, "BACKGROUND", nil, -1)
    icon.outline:SetPoint("TOPLEFT", -2, 2)
    icon.outline:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.outline:SetColorTexture(0, 0, 0, 1)
    icon.border = icon:CreateTexture(nil, "BORDER")
    icon.border:SetPoint("TOPLEFT", -1, 1)
    icon.border:SetPoint("BOTTOMRIGHT", 1, -1)
    icon.border:SetColorTexture(1, 0.12, 0.08, 1)
    icon.marker = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    icon.marker:SetPoint("BOTTOMRIGHT", 2, -2)
    icon.marker:SetText("!")
    icon.marker:SetTextColor(1, 1, 1)
    icon:Hide()
    self.overlays[source] = icon
    source:HookScript("OnHide", function() icon:Hide() end)
    source:HookScript("OnShow", function() if ns.initialized then self:Update(source, icon) end end)
    self.pending[source] = nil
end

function Frames:Update(source, icon)
    if not ns.db.options.icons or not source:IsVisible() then icon:Hide(); return end
    local unit = source.unit
    if not ns.Readable(unit) or type(unit) ~= "string" then icon:Hide(); return end
    local guid = select(1, ns.UnitIdentity(unit))
    if not guid or guid == ns.playerGUID then icon:Hide(); return end
    local entry = ns.db.records[guid]
    local state = entry and entry.state
    if not state then icon:Hide(); return end
    local layout = layoutFor(unit)
    if icon.layout ~= layout and not InCombatLockdown() then self:Place(source, icon, layout) end
    local used = state == "used"
    icon.texture:SetDesaturated(used)
    icon.texture:SetVertexColor(used and 1 or 0.9, 1, used and 1 or 0.9)
    icon.outline:SetShown(used)
    icon.border:SetShown(used)
    icon.marker:SetShown(used)
    icon:Show()
end

function Frames:Discover()
    if InCombatLockdown() then return end
    for source in pairs(self.pending) do self:Add(source) end
    if PartyFrame and PartyFrame.PartyMemberFramePool then
        for source in PartyFrame.PartyMemberFramePool:EnumerateActive() do self:Add(source) end
    end
    if CompactPartyFrame and CompactPartyFrame.memberUnitFrames then
        for _, source in ipairs(CompactPartyFrame.memberUnitFrames) do self:Add(source) end
    end
    if CompactRaidFrameContainer and CompactRaidFrameContainer.frameUpdateList then
        local lists = CompactRaidFrameContainer.frameUpdateList
        for _, source in ipairs(lists.normal or {}) do
            if source.memberUnitFrames then
                for _, member in ipairs(source.memberUnitFrames) do self:Add(member) end
            else
                self:Add(source)
            end
        end
    end
    for group = 1, 8 do
        for member = 1, 5 do self:Add(_G["CompactRaidGroup" .. group .. "Member" .. member]) end
    end
    for member = 1, 5 do self:Add(_G["CompactPartyFrameMember" .. member]) end
    for i = 1, 40 do self:Add(_G["CompactRaidFrame" .. i]) end
    for i = 1, 4 do self:Add(_G["PartyMemberFrame" .. i]) end
end

function Frames:InstallHooks()
    local function note(source)
        if ns.initialized and source and ns.Readable(source) then self.pending[source] = true end
    end
    if type(CompactUnitFrame_SetUnit) == "function" and not self.hooked.compact then
        hooksecurefunc("CompactUnitFrame_SetUnit", note)
        self.hooked.compact = true
    end
    if PartyMemberFrameMixin and type(PartyMemberFrameMixin.Setup) == "function" and not self.hooked.party then
        hooksecurefunc(PartyMemberFrameMixin, "Setup", note)
        self.hooked.party = true
    end
end

function Frames:Refresh()
    self:Discover()
    for source, icon in pairs(self.overlays) do
        if not InCombatLockdown() then icon:SetSize(ns.db.options.iconSize, ns.db.options.iconSize) end
        local ok, errorMessage = pcall(self.Update, self, source, icon)
        if not ok then icon:Hide(); ns.Debug("Frame icon: " .. ns.Text(errorMessage)) end
    end
end

function Frames:SetSize(size)
    size = math.max(10, math.min(24, math.floor(size + 0.5)))
    ns.db.options.iconSize = size
    if InCombatLockdown() then return end
    for _, icon in pairs(self.overlays) do icon:SetSize(size, size) end
end
