local _, ns = ...
ns.VERSION = "1.0.1"
ns.CREDIT = "Corwynn of <COZY> for inspiration & collaboration."
ns.ICON = "Interface\\Icons\\INV_Stone_04"
ns.roster, ns.units = {}, {}
ns.defaults = {icons = true, badge = true, minimap = true, sound = false, chat = false, iconSize = 14, locked = true}

function ns.Readable(value)
    return not (issecretvalue and issecretvalue(value))
end

function ns.Table(value)
    return ns.Readable(value) and type(value) == "table"
        and not (issecrettable and issecrettable(value))
end

function ns.Text(value)
    return ns.Readable(value) and tostring(value) or "unavailable"
end

function ns.Print(message)
    print("|cff80dca0StoneWatch|r: " .. message)
end

function ns.Debug(message)
    ns.lastError = message
end

function ns.Register(frame, event)
    if not C_EventUtils or C_EventUtils.IsEventValid(event) then
        pcall(frame.RegisterEvent, frame, event)
    end
end

function ns.UnitIdentity(unit)
    if not ns.Readable(unit) or type(unit) ~= "string" then return end
    local guid = UnitGUID(unit)
    if not ns.Readable(guid) or type(guid) ~= "string" then return end
    local name, realm = UnitFullName(unit)
    if not ns.Readable(name) or type(name) ~= "string" then return end
    if ns.Readable(realm) and type(realm) == "string" and realm ~= "" then
        name = name .. "-" .. realm
    end
    return guid, name
end

function ns.RefreshRoster()
    local roster, units = {}, {"player"}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    for _, unit in ipairs(units) do
        local guid, name = ns.UnitIdentity(unit)
        if guid then roster[guid] = {name = name, unit = unit} end
    end
    ns.roster, ns.units = roster, units
    ns.playerGUID = select(1, ns.UnitIdentity("player")) or ns.playerGUID
end

function ns.Restricted()
    if InCombatLockdown() then return true end
    if C_RestrictedActions and Enum.AddOnRestrictionType then
        for _, kind in ipairs({Enum.AddOnRestrictionType.Combat, Enum.AddOnRestrictionType.Encounter}) do
            if C_RestrictedActions.IsAddOnRestrictionActive(kind) then return true end
        end
    end
    for _, unit in ipairs(ns.units) do
        local fighting = UnitAffectingCombat(unit)
        if not ns.Readable(fighting) or fighting then return true end
    end
    return false
end

function ns.Refresh()
    if ns.initialized then
        if ns.UI then ns.UI:Refresh() end
        if ns.Frames then ns.Frames:Refresh() end
        if ns.Minimap then ns.Minimap:Refresh() end
        if ns.Options then ns.Options:Refresh() end
    end
end

function ns.Notify(entries)
    if #entries == 0 then return end
    local names = {}
    for _, entry in ipairs(entries) do names[#names + 1] = entry.name end
    table.sort(names)
    if ns.db.options.chat then
        ns.Print(table.concat(names, ", ") .. (#names == 1 and " used a healthstone." or " used healthstones."))
    end
    if ns.db.options.sound then
        PlaySound(SOUNDKIT and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or 856, "Master")
    end
    ns.Refresh()
end
