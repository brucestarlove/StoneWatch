local _, ns = ...
local Sync = {outgoing = {}, incoming = {}, peers = {}, nextSend = 0, nextHello = 0, nextReply = 0}
ns.Sync = Sync
local PREFIX = "StoneWatch"

local function normalized(name)
    return name:lower():gsub("%s+", "-")
end

local function integer(value)
    return type(value) == "number" and value >= 0 and value < 1e12 and value == math.floor(value)
end

function Sync:Channel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if GetNumSubgroupMembers() > 0 then return "PARTY" end
end

function Sync:Blocked()
    if not self.worldReady or ns.Restricted() then return true end
    if C_ChatInfo.InChatMessagingLockdown then
        local restricted = C_ChatInfo.InChatMessagingLockdown()
        if not ns.Readable(restricted) or restricted then return true end
    end
    if C_RestrictedActions and Enum.AddOnRestrictionType.Chat then
        if C_RestrictedActions.IsAddOnRestrictionActive(Enum.AddOnRestrictionType.Chat) then return true end
    end
    return false
end

function Sync:Initialize()
    ns.db.syncSequence = integer(ns.db.syncSequence) and ns.db.syncSequence or 0
    if not C_ChatInfo or not C_ChatInfo.RegisterAddonMessagePrefix or not C_ChatInfo.SendAddonMessage then return end
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
    self.ready = ok and ns.Readable(result) and
        (result == Enum.RegisterAddonMessagePrefixResult.Success or result == Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix)
    if not self.ready then ns.Debug("Refill sync: addon message prefix could not be registered.") end
end

function Sync:Stamp(entry, stamp)
    ns.db.syncSequence = ns.db.syncSequence + 1
    entry.supplierGUID = ns.playerGUID
    -- Advance the previous refill even when two trades complete in the
    -- same server second.
    entry.supplyStamp = stamp or math.max(GetServerTime(), (entry.supplyStamp or 0) + 1)
    entry.supplySequence = ns.db.syncSequence
end

function Sync:EnterWorld()
    self.worldReady, self.groupDirty = true, true
    local now = GetServerTime()
    local offset = now - time()
    for _, entry in pairs(ns.db.records) do
        if not entry.supplierGUID then
            self:Stamp(entry, math.max(0, math.min(now, (entry.suppliedAt or time()) + offset)))
        end
    end
end

function Sync:GroupChanged()
    self.groupDirty = true
end

function Sync:Queue(entry, snapshot)
    if not self.ready or entry.supplierGUID ~= ns.playerGUID or not ns.roster[entry.guid] then return end
    local old = self.outgoing[entry.guid]
    self.outgoing[entry.guid] = {entry = entry, snapshot = snapshot and not (old and old.entry == entry and not old.snapshot)}
end

function Sync:QueueOwned()
    for _, entry in pairs(ns.db.records) do self:Queue(entry, true) end
end

function Sync:PublishSupply(entry)
    self:Stamp(entry)
    self:Queue(entry, false)
    self:Flush()
end

function Sync:PublishUse(entry)
    entry.usedStamp = GetServerTime()
    self:Queue(entry, false)
end

function Sync:ClearQueues()
    self.incoming, self.outgoing = {}, {}
    self.replyPending = false
end

function Sync:ValidSender(sender, supplierGUID)
    local member = ns.roster[supplierGUID]
    if not member or supplierGUID == ns.playerGUID then return false end
    local name = normalized(sender)
    if name == normalized(member.name) then return true end
    -- Some clients omit the realm for local senders. Accept a short name
    -- only when it identifies exactly one group member.
    if name ~= normalized(member.name):match("^[^-]+") then return false end
    for guid, other in pairs(ns.roster) do
        if guid ~= supplierGUID and name == normalized(other.name):match("^[^-]+") then return false end
    end
    return true
end

function Sync:Receive(prefix, message, channel, sender)
    if not self.ready or not ns.Readable(prefix) or prefix ~= PREFIX then return end
    if not ns.Readable(message) or type(message) ~= "string" or #message > 240
        or not ns.Readable(sender) or type(sender) ~= "string"
        or not ns.Readable(channel) or channel ~= self:Channel() then return end
    local requester = message:match("^1|Q|([^|]+)$")
    if requester then
        if self:ValidSender(sender, requester) then
            self.peers[requester] = true
            self.replyPending = true
        end
        return
    end
    local kind, supplier, guid, stamp, sequence, ids, usedStamp, spellID, healing =
        message:match("^1|([ES])|([^|]+)|([^|]+)|(%d+)|(%d+)|([%d,]+)|(%d+)|(%d+)|([^|]+)$")
    if not kind or not self:ValidSender(sender, supplier) or not ns.roster[guid] then return end
    stamp, sequence, usedStamp, spellID, healing = tonumber(stamp), tonumber(sequence), tonumber(usedStamp), tonumber(spellID), tonumber(healing)
    if not integer(stamp) or stamp > GetServerTime() + 60 or not integer(sequence) or sequence == 0
        or not integer(usedStamp) or usedStamp > GetServerTime() + 60 or not integer(spellID)
        or type(healing) ~= "number" or healing < 0 or healing >= 1e12 or healing ~= healing then return end
    if usedStamp == 0 then
        if spellID ~= 0 or healing ~= 0 then return end
    elseif spellID == 0 or healing <= 0 then return end
    local items, tokens = {}, {}
    for token in ids:gmatch("%d+") do
        local itemID = tonumber(token)
        if ns.Tracking.items[itemID] == nil or items[itemID] ~= nil or #tokens >= 6 then return end
        items[itemID] = ns.Tracking.items[itemID]
        tokens[#tokens + 1] = tostring(itemID)
    end
    if #tokens == 0 or table.concat(tokens, ",") ~= ids then return end
    local record = {guid = guid, supplierGUID = supplier, supplyStamp = stamp, supplySequence = sequence,
        items = items, usedStamp = usedStamp, spellID = spellID, healing = healing, snapshot = kind == "S"}
    local old = self.incoming[guid]
    if not old or ns.model:NewerSupply(record, old) then
        self.incoming[guid] = record
    elseif ns.model:SameSupply(record, old) then
        if record.usedStamp > 0 and old.usedStamp == 0 then
            self.incoming[guid] = record
        elseif record.usedStamp == old.usedStamp and not record.snapshot then
            old.snapshot = false
        end
    end
    self.peers[supplier] = true
end

function Sync:Apply(record)
    if not ns.roster[record.guid] or not ns.roster[record.supplierGUID] then return end
    local entry = ns.db.records[record.guid]
    if not ns.model:SameSupply(record, entry) then
        if not ns.model:NewerSupply(record, entry) then return end
        -- Session IDs belong to this client. Build a fresh local baseline
        -- rather than importing another client's damage meter IDs.
        entry = ns.model:Supply(record.guid, ns.roster[record.guid].name, record.items,
            ns.Tracking:Sessions(), time(), record)
    end
    if record.usedStamp > 0 then
        local used = ns.model:MarkUsed(entry, record.spellID, record.healing,
            time() + record.usedStamp - GetServerTime(), nil, not record.snapshot)
        if used then
            entry.usedStamp = record.usedStamp
            if not record.snapshot then return used end
        end
    end
end

function Sync:Encode(pending)
    local entry, ids = pending.entry, {}
    for itemID in pairs(entry.items) do ids[#ids + 1] = itemID end
    table.sort(ids)
    for i, itemID in ipairs(ids) do ids[i] = tostring(itemID) end
    local used = entry.state == "used"
    local stamp = used and (entry.usedStamp or math.max(entry.supplyStamp, (entry.usedAt or time()) + GetServerTime() - time())) or 0
    return table.concat({"1", pending.snapshot and "S" or "E", entry.supplierGUID, entry.guid,
        tostring(entry.supplyStamp), tostring(entry.supplySequence), table.concat(ids, ","),
        tostring(stamp), tostring(used and entry.usedSpell or 0), tostring(used and (entry.usedHealing or 1) or 0)}, "|")
end

function Sync:Flush()
    if not self.ready or self:Blocked() or GetTime() < self.nextSend then return end
    local channel = self:Channel()
    if not channel then return end
    local chosen, guid
    for target, pending in pairs(self.outgoing) do
        if ns.roster[target] and ns.db.records[target] == pending.entry and pending.entry.supplierGUID == ns.playerGUID then
            if not chosen or not pending.snapshot then chosen, guid = pending, target end
            if not pending.snapshot then break end
        else
            self.outgoing[target] = nil
        end
    end
    local hello = self.helloPending and GetTime() >= (self.helloAllowed or 0)
    if not hello and not chosen then return end
    local message = hello and ("1|Q|" .. ns.playerGUID) or self:Encode(chosen)
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, message, channel)
    self.nextSend = GetTime() + (ok and 0.25 or 2)
    self.lastSendResult = ok and ns.Text(result) or "error"
    if ok and ns.Readable(result) and result == Enum.SendAddonMessageResult.Success then
        if hello then
            self.helloPending, self.nextHello, self.helloAllowed = false, GetTime() + 30, GetTime() + 2
        else
            self.outgoing[guid] = nil
        end
    else
        self.nextSend = GetTime() + 2
    end
end

function Sync:Tick()
    if not self.ready then return end
    if self:Blocked() then self.wasBlocked = true; return end
    if self.groupDirty or self.wasBlocked then
        ns.RefreshRoster()
        self.groupDirty = false
    end
    local members = {}
    for guid in pairs(ns.roster) do members[#members + 1] = guid end
    table.sort(members)
    local channel = self:Channel()
    local group = (channel or "") .. "|" .. table.concat(members, ",")
    if group ~= self.group or self.wasBlocked then
        self.group, self.wasBlocked = group, false
        self.helloPending = channel ~= nil
        self:QueueOwned()
    end
    for guid in pairs(self.peers) do if not ns.roster[guid] then self.peers[guid] = nil end end
    if not channel then self.incoming, self.outgoing = {}, {}; return end
    if GetTime() >= self.nextHello then self.helloPending = true end
    local notices = {}
    local incoming = self.incoming
    self.incoming = {}
    for _, record in pairs(incoming) do
        local used = self:Apply(record)
        if used then notices[#notices + 1] = used end
    end
    ns.Notify(notices)
    if self.replyPending and GetTime() >= self.nextReply then
        self.replyPending, self.nextReply = false, GetTime() + 2
        self:QueueOwned()
    end
    self:Flush()
end

function Sync:Status()
    if not self.ready then return "unavailable" end
    local peers, queued = 0, 0
    for guid in pairs(self.peers) do if ns.roster[guid] then peers = peers + 1 end end
    for _ in pairs(self.outgoing) do queued = queued + 1 end
    return "automatic | peers seen: " .. peers .. " | queued: " .. queued .. " | last send: " .. (self.lastSendResult or "none")
end
