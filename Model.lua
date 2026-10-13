local _, ns = ...
local Model = {}
ns.Model = Model
Model.__index = Model

function Model.New(db)
    db.records = db.records or {}
    db.history = db.history or {}
    db.meterEpoch = db.meterEpoch or 1
    return setmetatable({db = db}, Model)
end

function Model:Token(sessionID)
    return self.db.meterEpoch .. ":" .. sessionID
end

function Model:Supply(guid, name, items, ignoredSessions, now, supply)
    local old = self.db.records[guid]
    local copiedItems, ignored = {}, {}
    for itemID, spellID in pairs(items) do copiedItems[itemID] = spellID end
    if ignoredSessions then
        for sessionID in pairs(ignoredSessions) do ignored[self:Token(sessionID)] = true end
    end
    local entry = {
        guid = guid, name = name, items = copiedItems, state = "given", suppliedAt = now,
        revision = old and old.revision + 1 or 1, ignored = ignored,
        primePending = ignoredSessions == nil,
        supplierGUID = supply and supply.supplierGUID,
        supplyStamp = supply and supply.supplyStamp or (old and old.supplyStamp),
        supplySequence = supply and supply.supplySequence,
    }
    self.db.records[guid] = entry
    return entry
end

function Model:SameSupply(a, b)
    return a and b and a.supplierGUID == b.supplierGUID
        and a.supplyStamp == b.supplyStamp and a.supplySequence == b.supplySequence
end

function Model:NewerSupply(a, b)
    if not b or not b.supplyStamp then return true end
    if a.supplyStamp ~= b.supplyStamp then return a.supplyStamp > b.supplyStamp end
    if a.supplierGUID == b.supplierGUID then return a.supplySequence > b.supplySequence end
    return a.supplierGUID > b.supplierGUID
end

function Model:Prime(entry, sessions)
    if not entry.primePending then return end
    for sessionID in pairs(sessions) do entry.ignored[self:Token(sessionID)] = true end
    entry.primePending = false
end

function Model:Observe(entry, sessionID, totals, now)
    if entry.state ~= "given" or entry.primePending or entry.ignored[self:Token(sessionID)] then return end
    local matched
    for _, spellID in pairs(entry.items) do
        if spellID and totals[spellID] and totals[spellID] > 0 then matched = spellID; break end
    end
    if not matched then return end
    return self:MarkUsed(entry, matched, totals[matched], now, sessionID)
end

function Model:MarkUsed(entry, spellID, healing, now, sessionID, recordHistory)
    if entry.state ~= "given" then return end
    entry.state, entry.usedAt, entry.usedSpell, entry.usedSession = "used", now, spellID, sessionID
    entry.usedHealing = healing
    if recordHistory ~= false then
        table.insert(self.db.history, 1, {
            guid = entry.guid, name = entry.name, at = now, spellID = spellID,
            healing = healing, sessionID = sessionID,
        })
        while #self.db.history > 30 do table.remove(self.db.history) end
    end
    return entry
end

function Model:ResetMeter()
    self.db.meterEpoch = self.db.meterEpoch + 1
end

function Model:Clear()
    self.db.records, self.db.history = {}, {}
end

function Model:Counts(roster)
    local given, used = 0, 0
    for guid in pairs(roster) do
        local entry = self.db.records[guid]
        if entry then
            if entry.state == "used" then used = used + 1 else given = given + 1 end
        end
    end
    return given, used
end
