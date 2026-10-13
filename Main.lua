local addon, ns = ...
local frame = CreateFrame("Frame")
local function initialize()
    StoneWatchDB = type(StoneWatchDB) == "table" and StoneWatchDB or {}
    ns.db = StoneWatchDB
    ns.db.options = type(ns.db.options) == "table" and ns.db.options or {}
    for key, value in pairs(ns.defaults) do
        if type(ns.db.options[key]) ~= type(value) then ns.db.options[key] = value end
    end
    ns.db.options.iconSize = math.max(10, math.min(24, math.floor(ns.db.options.iconSize + 0.5)))
    ns.db.minimapAngle = type(ns.db.minimapAngle) == "number" and ns.db.minimapAngle % 360 or 225
    ns.db.options.provider = nil
    ns.model = ns.Model.New(ns.db)
    ns.RefreshRoster()
    local _, class = UnitClass("player")
    ns.isWarlock = ns.Readable(class) and class == "WARLOCK"
    ns.initialized = true
    ns.Tracking:LoadItems(true)
    ns.Sync:Initialize()
    ns.UI:Create()
    ns.Minimap:Create()
    ns.Options:Create()
    ns.Frames:InstallHooks()
    ns.Refresh()
    ns.ticker = C_Timer.NewTicker(0.75, function()
        ns.Sync:Tick()
        if ns.pendingScan and not ns.Tracking.scanning and not ns.Restricted() then ns.Tracking:RequestScan(1) end
        ns.Refresh()
    end)
end

SLASH_STONEWATCH1 = "/stonewatch"
SLASH_STONEWATCH2 = "/sw"
SlashCmdList.STONEWATCH = function(message)
    if not ns.initialized then return end
    local command, value = message:lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "" then
        ns.UI:Toggle()
    elseif command == "options" then
        ns.Options:Open()
    elseif command == "scan" then
        ns.Tracking:CancelScan()
        ns.Tracking:RequestScan(0)
        ns.Print("Checking healing data after combat.")
    elseif command == "clear" then
        ns.model:Clear()
        ns.Sync:ClearQueues()
        ns.Refresh()
        ns.Print("Local tracked trades and recent uses cleared.")
    elseif command == "unlock" or command == "lock" then
        ns.db.options.locked = command == "lock"
        ns.Print(command == "lock" and "HUD locked." or "Drag the HUD with the left mouse button. /sw lock when finished.")
    elseif command == "size" and tonumber(value) then
        ns.Frames:SetSize(math.max(10, math.min(24, tonumber(value))))
        ns.Refresh()
    elseif command == "status" then
        ns.Print(ns.Tracking:Diagnostic())
    elseif command == "reset" then
        ns.UI:ResetPosition()
        ns.Print("HUD position reset.")
    elseif ns.defaults[command] ~= nil and type(ns.defaults[command]) == "boolean" then
        ns.db.options[command] = value ~= "off"
        ns.Refresh()
    else
        ns.Print("/sw opens the list; options, scan, clear, status, unlock, lock, size 14, reset; icons/badge/minimap/sound/chat on|off.")
    end
end

for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED", "ENCOUNTER_START", "ENCOUNTER_END", "BAG_UPDATE_DELAYED",
    "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED", "ITEM_DATA_LOAD_RESULT", "CVAR_UPDATE",
    "TRADE_SHOW", "TRADE_UPDATE", "TRADE_PLAYER_ITEM_CHANGED", "TRADE_ACCEPT_UPDATE",
    "TRADE_CLOSED", "TRADE_REQUEST_CANCEL", "UI_INFO_MESSAGE", "UI_ERROR_MESSAGE",
    "DAMAGE_METER_COMBAT_SESSION_UPDATED", "DAMAGE_METER_CURRENT_SESSION_UPDATED", "DAMAGE_METER_RESET", "CHAT_MSG_ADDON",
}) do ns.Register(frame, event) end

frame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addon and not ns.initialized then initialize() end
        if ns.initialized then
            ns.Frames:InstallHooks()
            ns.Minimap:Create()
            if (...) == "Details" then ns.Tracking:RequestScan(1) end
            ns.Refresh()
        end
        return
    end
    if not ns.initialized then return end
    if event == "PLAYER_ENTERING_WORLD" then
        local initialLogin = ...
        if initialLogin then ns.db.records = {}; ns.fightRoster = nil end
        ns.RefreshRoster()
        ns.Sync:EnterWorld()
        ns.Tracking.stock = nil
        ns.Tracking:RequestScan(2)
    elseif event == "GROUP_ROSTER_UPDATE" then
        ns.RefreshRoster()
        ns.Sync:GroupChanged()
        ns.Tracking:RequestScan(2)
    elseif event == "PLAYER_REGEN_DISABLED" or event == "ENCOUNTER_START" then
        ns.RefreshRoster()
        ns.fightRoster = {}
        for guid, member in pairs(ns.roster) do ns.fightRoster[guid] = member end
        ns.Tracking:CancelScan()
        ns.pendingScan = true
        ns.Sync.wasBlocked = true
    elseif event == "PLAYER_REGEN_ENABLED" or event == "ENCOUNTER_END" then
        ns.Tracking:RequestScan(2)
    elseif event == "DAMAGE_METER_COMBAT_SESSION_UPDATED" or event == "DAMAGE_METER_CURRENT_SESSION_UPDATED" then
        ns.pendingScan = true
        if not ns.Restricted() then ns.Tracking:RequestScan(2) end
    elseif event == "DAMAGE_METER_RESET" then
        ns.model:ResetMeter()
        ns.Tracking:CancelScan()
        ns.pendingScan = false
    elseif event == "BAG_UPDATE_DELAYED" then
        ns.Tracking.stock = nil
    elseif event == "ITEM_DATA_LOAD_RESULT" then
        ns.Tracking:LoadItems(false)
    elseif event == "TRADE_SHOW" then
        ns.Tracking:BeginTrade()
    elseif event == "TRADE_PLAYER_ITEM_CHANGED" or event == "TRADE_UPDATE" then
        ns.Tracking:UpdateTrade()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        ns.Tracking:AcceptTrade(...)
    elseif event == "TRADE_CLOSED" then
        ns.Tracking:CloseTrade()
    elseif event == "TRADE_REQUEST_CANCEL" then
        ns.Tracking:CancelTrade()
    elseif event == "UI_INFO_MESSAGE" or event == "UI_ERROR_MESSAGE" then
        local messageID, message = ...
        ns.Tracking:CompleteTrade(message, messageID)
    elseif event == "CHAT_MSG_ADDON" then
        ns.Sync:Receive(...)
    end
    ns.Refresh()
end)
ns.eventFrame = frame
