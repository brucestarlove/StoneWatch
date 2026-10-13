local _, ns = ...
local Tracking = {items = {}, scanGeneration = 0}
ns.Tracking = Tracking
local confirmed = {[5512] = 6262, [5511] = 6263, [5509] = 5720, [5510] = 5723, [9421] = 11732}
for itemID, spellID in pairs(confirmed) do Tracking.items[itemID] = spellID end
for _, itemID in ipairs({19004,19005,19006,19007,19008,19009,19010,19011,19012,19013}) do
    Tracking.items[itemID] = false
end

local meterMethods = {"GetAvailableCombatSessions", "GetCombatSessionFromID", "GetCombatSessionSourceFromID"}
local function compatibleMeter(meter)
    if not ns.Table(meter) then return false end
    for _, method in ipairs(meterMethods) do
        if not ns.Readable(meter[method]) or type(meter[method]) ~= "function" then return false end
    end
    return true
end

function Tracking:Meter()
    -- Forever's Details uses the same combat sessions, so loading it later
    -- preserves the baselines of healthstones already traded.
    if ns.Table(_G.Details) and compatibleMeter(_G.Details.DM) then
        return _G.Details.DM, "Details"
    end
    if compatibleMeter(C_DamageMeter) then return C_DamageMeter, "Blizzard" end
end

function Tracking:MeterStatus()
    local meter, source = self:Meter()
    if not meter then return false, "Damage meter data is unavailable." end
    if source == "Blizzard" and not C_CVar.GetCVarBool("damageMeterEnabled") then
        return false, "Enable Blizzard's damage meter to record healthstone use."
    end
    return true
end

function Tracking:LoadItems(request)
    self.stock = nil
    for itemID in pairs(self.items) do
        local _, spellID = C_Item.GetItemSpell(itemID)
        if ns.Readable(spellID) and type(spellID) == "number" then
            self.items[itemID] = spellID
        elseif request and C_Item.RequestLoadItemDataByID then
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    if ns.model then
        for _, entry in pairs(ns.db.records) do
            for itemID in pairs(entry.items) do entry.items[itemID] = self.items[itemID] end
        end
    end
end

function Tracking:OwnStock()
    if self.stock then return self.stock end
    local total = 0
    for itemID in pairs(self.items) do
        local count = C_Item.GetItemCount(itemID, false, false)
        if ns.Readable(count) and type(count) == "number" then total = total + count end
    end
    self.stock = total
    return total
end

function Tracking:Sessions()
    local meter = self:Meter()
    if not meter then return end
    local ok, available = pcall(meter.GetAvailableCombatSessions)
    if not ok or not ns.Table(available) then return end
    local sessions = {}
    for _, entry in ipairs(available) do
        if not ns.Table(entry) or not ns.Readable(entry.sessionID) or type(entry.sessionID) ~= "number" then return end
        sessions[entry.sessionID] = true
    end
    return sessions
end

function Tracking:ReadTotals(sessionID, guid)
    local meter = self:Meter()
    if not meter then return end
    local ok, source = pcall(meter.GetCombatSessionSourceFromID,
        sessionID, Enum.DamageMeterType.HealingDone, guid, nil)
    if not ok then ns.Debug("Meter query: " .. ns.Text(source)); return end
    if not ns.Table(source) or not ns.Table(source.combatSpells) then return end
    local totals = {}
    for _, spell in ipairs(source.combatSpells) do
        if not ns.Table(spell) or not ns.Readable(spell.spellID) or not ns.Readable(spell.totalAmount)
            or type(spell.spellID) ~= "number" or type(spell.totalAmount) ~= "number" then return end
        totals[spell.spellID] = (totals[spell.spellID] or 0) + spell.totalAmount
    end
    return totals
end

function Tracking:ReadSources(sessionID)
    local meter = self:Meter()
    if not meter then return end
    local ok, session = pcall(meter.GetCombatSessionFromID, sessionID, Enum.DamageMeterType.HealingDone)
    if not ok or not ns.Table(session) or not ns.Table(session.combatSources) then return end
    local sources, unknown = {}, false
    for _, source in ipairs(session.combatSources) do
        if ns.Table(source) and ns.Readable(source.sourceGUID) then
            if type(source.sourceGUID) == "string" then sources[source.sourceGUID] = true end
        else
            unknown = true
        end
    end
    return sources, unknown
end

function Tracking:Scan()
    if ns.Restricted() then return false, "Waiting until the group leaves combat." end
    ns.RefreshRoster()
    local sessions = self:Sessions()
    if not sessions then
        local _, reason = self:MeterStatus()
        return false, reason or "Waiting for readable damage meter sessions."
    end
    local notices, complete, cache = {}, true, {}
    for guid, entry in pairs(ns.db.records) do
        if (ns.roster[guid] or (ns.fightRoster and ns.fightRoster[guid])) and entry.state == "given" then
            if entry.primePending then
                ns.model:Prime(entry, sessions)
            else
                for sessionID in pairs(sessions) do
                    if entry.state == "given" and not entry.ignored[ns.model:Token(sessionID)] then
                        if not cache[sessionID] then
                            local sources, unknown = self:ReadSources(sessionID)
                            cache[sessionID] = {sources = sources, unknown = unknown}
                        end
                        local session = cache[sessionID]
                        local totals
                        if session.sources and session.sources[guid] then
                            totals = self:ReadTotals(sessionID, guid)
                        elseif session.sources and not session.unknown then
                            totals = {}
                        end
                        if totals then
                            local used = ns.model:Observe(entry, sessionID, totals, time())
                            if used then
                                ns.Sync:PublishUse(used)
                                notices[#notices + 1] = used
                            end
                        else
                            complete = false
                        end
                    end
                end
            end
        end
    end
    ns.Notify(notices)
    ns.Refresh()
    return complete, complete and nil or "Some healing data is still unavailable."
end

function Tracking:RequestScan(delay)
    if self.scanning then return end
    self.scanning = true
    self.scanGeneration = self.scanGeneration + 1
    local generation, attempts = self.scanGeneration, 0
    local function poll()
        if generation ~= self.scanGeneration or not ns.initialized then return end
        attempts = attempts + 1
        local ok, complete, reason = pcall(self.Scan, self)
        if not ok then ns.Debug("Scan: " .. ns.Text(complete)) end
        ns.pendingScan = not ok or not complete
        ns.scanReason = ok and reason or "Healing data could not be read yet."
        ns.Refresh()
        if ns.pendingScan and attempts < 60 then
            C_Timer.After(2, poll)
        elseif ns.pendingScan then
            self.scanning = false
            ns.Debug(ns.scanReason or "Scan timed out; the next meter update will retry.")
        else
            self.scanning = false
        end
    end
    C_Timer.After(delay or 2, poll)
end

function Tracking:CancelScan()
    self.scanGeneration = self.scanGeneration + 1
    self.scanning = false
end

local function tradeItems()
    local items = {}
    for slot = 1, 6 do
        local _, _, _, _, _, _, _, itemID = GetTradePlayerItemInfo(slot)
        if not ns.Readable(itemID) then return end
        if type(itemID) ~= "number" then
            local link = GetTradePlayerItemLink(slot)
            if not ns.Readable(link) then return end
            itemID = type(link) == "string" and tonumber(link:match("item:(%d+)")) or nil
        end
        if itemID and Tracking.items[itemID] ~= nil then items[itemID] = Tracking.items[itemID] end
    end
    return items
end

function Tracking:UpdateTrade()
    local trade = self.trade
    if not trade or trade.closed or trade.completed or trade.accepted then return end
    local guid, name = ns.UnitIdentity("NPC")
    if not guid then return end
    trade.guid, trade.name = guid, name
    local items = tradeItems()
    if items then trade.items = items end
end

function Tracking:AcceptTrade(playerAccepted, targetAccepted)
    local trade = self.trade
    if not trade or trade.closed or trade.completed or trade.acceptedByBoth then return end
    if not ns.Readable(playerAccepted) or not ns.Readable(targetAccepted) then return end
    -- Acceptance can arrive after the item slots have cleared. Keep the
    -- last offered items until success, cancellation, or an unaccept.
    trade.accepted = playerAccepted == 1
    trade.acceptedByBoth = trade.accepted and targetAccepted == 1
    if not trade.accepted then self:UpdateTrade() end
end

function Tracking:BeginTrade()
    self.closedTrade = nil
    self.trade = {items = {}, opened = GetTime()}
    self:UpdateTrade()
end

function Tracking:CloseTrade()
    local trade = self.trade
    if not trade or trade.closed then return end
    trade.closed, trade.closedAt = true, GetTime()
    self.closedTrade, self.trade = trade, nil
    C_Timer.After(5, function() if self.closedTrade == trade then self.closedTrade = nil end end)
end

function Tracking:CompleteTrade(message, messageID)
    if not ns.Readable(message) then return end
    local trade = self.closedTrade or self.trade
    if not trade or trade.completed then return end
    if message ~= ERR_TRADE_COMPLETE then
        if not trade.closed and GetGameMessageInfo and ns.Readable(messageID) and type(messageID) == "number" then
            local kind = GetGameMessageInfo(messageID)
            if ns.Readable(kind) and type(kind) == "string" and kind:match("^ERR_TRADE") then
                trade.accepted, trade.acceptedByBoth = false, false
                self:UpdateTrade()
            end
        end
        return
    end
    trade.completed = true
    if not next(trade.items) then return end
    if not trade.guid then
        ns.Debug("A healthstone trade completed, but the recipient identity was unavailable.")
        return
    end
    ns.RefreshRoster()
    local entry = ns.model:Supply(trade.guid, trade.name, trade.items, self:Sessions(), time())
    ns.Sync:PublishSupply(entry)
    ns.Refresh()
end

function Tracking:CancelTrade()
    -- Once both players accept, the server's completion message decides
    -- the outcome even if closing the window also raises a cancel event.
    if self.trade and not self.trade.acceptedByBoth then self.trade.completed = true end
    if self.closedTrade and not self.closedTrade.acceptedByBoth then self.closedTrade.completed = true end
end

function Tracking:Diagnostic()
    local version, build = GetBuildInfo()
    local meter, source = self:Meter()
    local sessions = self:Sessions()
    local count = 0
    if sessions then for _ in pairs(sessions) do count = count + 1 end end
    local given, used = ns.model:Counts(ns.roster)
    return table.concat({
        "StoneWatch " .. ns.VERSION .. " | client " .. ns.Text(version) .. " build " .. ns.Text(build),
        "Own stones: " .. self:OwnStock() .. " | given: " .. given .. " | used: " .. used,
        "Data source: " .. (source or "unavailable") .. " (automatic) | API available: " .. tostring(meter ~= nil) .. " | sessions: " .. count,
        "Pending scan: " .. tostring(not not ns.pendingScan),
        "Refill sync: " .. ns.Sync:Status(),
        "Last issue: " .. (ns.lastError or "none"),
    }, "\n")
end
