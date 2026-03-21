-- Copyright The Eavesdropper Authors
-- SPDX-License-Identifier: Apache-2.0

---@type EavesdropperConstants
local Constants = ED.Constants;

---@class PlayerCacheEntryBySender
---@field guid string?
---@field time number

---@class PlayerCacheEntryByGUID
---@field sender string
---@field time number

---@class PlayerCacheEntryByTime
---@field guid string?
---@field sender string

---@class EavesdropperPlayerCache
---@field bySender table<string, PlayerCacheEntryBySender>
---@field byGUID table<string, PlayerCacheEntryByGUID>
---@field byTime table<number, PlayerCacheEntryByTime>
local PlayerCache = {};
PlayerCache.bySender = {};
PlayerCache.byGUID   = {};
PlayerCache.byTime   = {};

---@type EavesdropperUtils
local Utils = ED.Utils;

---Sorted timestamps for byTime, newest first. Used for recent-activity iteration.
---@type number[]
local sortedTimes = {};

---Returns a unique GetTime() value for use as a byTime key.
---@return number
function PlayerCache:getUniqueTime()
	local t = GetTime();
	while self.byTime[t] do
		t = t + Constants.PLAYER_CACHE.TIME;
	end
	return t;
end

---Removes cache entries older than ttl seconds and rebuilds sortedTimes if anything changed.
---@param ttl number Time to live in seconds
function PlayerCache:PruneOldEntries(ttl)
	if not ttl or ttl <= 0 then return; end

	local now = GetTime();
	local changed = false;

	for t, data in pairs(self.byTime) do
		if t + ttl < now then
			if data.sender then
				self.bySender[data.sender] = nil;
			end
			if data.guid then
				self.byGUID[data.guid] = nil;
			end
			self.byTime[t] = nil;
			changed = true;
		end
	end

	-- Rebuild sortedTimes only if something was pruned.
	if changed then
		wipe(sortedTimes);
		for t in pairs(self.byTime) do
			tinsert(sortedTimes, t);
		end
		table.sort(sortedTimes, function(a, b) return a > b; end);
	end
end

---Loads the player cache from a saved table, rebuilds sortedTimes, and prunes expired entries.
---@param cache table? Saved player cache
---@param ttl number? Time to live in seconds
function PlayerCache:LoadFromSaved(cache, ttl)
	cache = cache or {};
	ttl = ttl or Constants.PLAYER_CACHE.DEFAULT_TTL;

	self.bySender = cache.bySender or {};
	self.byGUID   = cache.byGUID   or {};
	self.byTime   = cache.byTime   or {};

	-- Build sortedTimes
	wipe(sortedTimes);
	for t in pairs(self.byTime) do
		tinsert(sortedTimes, t);
	end
	table.sort(sortedTimes, function(a, b) return a > b; end);

	self:PruneOldEntries(ttl);
end

---Inserts or updates a sender  <-> GUID mapping across all three indices and persists to CharDB.
---@param sender string
---@param guid string?
---@return string sender Full sender name with realm
---@return string? guid GUID associated with sender
function PlayerCache:InsertAndRetrieve(sender, guid)
	if (not sender or sender == "") and guid then
		sender = self:GetSenderDataFromGUID(guid);
		if not sender then return; end
	end
	if not sender or sender == "" then return; end
	if guid and not canaccessvalue(guid) then return; end

	if not Utils.HasRealmSuffix(sender) then
		for fullName, entry in pairs(self.bySender) do
			if fullName:match("^" .. sender .. "%-") then
				sender = fullName;
				guid = entry.guid or guid;
				break;
			end
		end
	end

	-- Migrate history entries stored under the bare name to the full Name-Realm key.
	if ED.ChatHistory and Utils.HasRealmSuffix(sender) then
		local bareName = Utils.StripRealmSuffix(sender);
		local bareHistory = ED.ChatHistory.history[bareName];

		if bareHistory and #bareHistory > 0 then
			local target = ED.ChatHistory.history[sender] or {};
			ED.ChatHistory.history[sender] = target;

			for _, e in ipairs(bareHistory) do
				e.s = sender;
				if not e.g and guid then
					e.g = guid;
				end
				tinsert(target, e);
			end
			ED.ChatHistory.history[bareName] = nil;
		end
	end

	-- Remove the old byTime slot for this sender before reinserting.
	local oldEntry = self.bySender[sender];
	if oldEntry and oldEntry.time then
		self.byTime[oldEntry.time] = nil;
		for i = #sortedTimes, 1, -1 do
			if sortedTimes[i] == oldEntry.time then
				tremove(sortedTimes, i);
				break;
			end
		end
	end

	-- Evict any bare-name entry now that we have the full Name-Realm.
	if Utils.HasRealmSuffix(sender) then
		local bareName = Utils.StripRealmSuffix(sender);
		self.bySender[bareName] = nil;
	end

	local cacheTime = self:getUniqueTime();

	self.bySender[sender] = { guid = guid, time = cacheTime };
	if guid then
		self.byGUID[guid] = { sender = sender, time = cacheTime };
	end
	self.byTime[cacheTime] = { sender = sender, guid = guid };
	tinsert(sortedTimes, 1, cacheTime); -- Newest first.

	-- Persist immediately to CharDB.
	if EavesdropperCharDB then
		EavesdropperCharDB.playerCache = {
			bySender = self.bySender,
			byGUID   = self.byGUID,
			byTime   = self.byTime,
		};
	end

	return sender, guid;
end

---Returns the bySender entry for an exact or bare name match.
---@param name string
---@return PlayerCacheEntryBySender? entry
function PlayerCache:GetSenderEntry(name)
	if not name or name == "" then return; end
	local entry = self.bySender[name];
	if entry then return entry; end

	local bareName = name:match("^([^%-]+)");
	if bareName then
		for fullName, data in pairs(self.bySender) do
			if fullName:match("^" .. bareName .. "%-") then
				return data;
			end
		end
	end
end

---Returns the most recently seen full sender name and bySender entry for a given name.
---@param name string
---@return string? sender
---@return PlayerCacheEntryBySender? entry
function PlayerCache:GetSenderEntryByTime(name)
	if not name or name == "" then return; end
	local bareName = name:match("^([^%-]+)") or name;

	for _, t in ipairs(sortedTimes) do
		local data = self.byTime[t];
		if data and data.sender then
			local sender = data.sender;
			if sender == name or sender:match("^" .. bareName .. "%-") then
				return sender, self.bySender[sender];
			end
		end
	end
end

---Resolves a sender name from a GUID, backfilling the cache from the WoW API if needed.
---@param guid string
---@return string? sender
function PlayerCache:GetSenderDataFromGUID(guid)
	if not guid then return; end
	if not canaccessvalue(guid) then return; end

	local entry = self.byGUID[guid];
	if entry then return entry.sender; end

	local _, _, _, _, _, name, realm = GetPlayerInfoByGUID(guid);
	if not name then return; end
	if not realm or realm == "" then realm = GetNormalizedRealmName(); end
	if not realm then return; end

	local sender = name .. "-" .. realm;
	self:InsertAndRetrieve(sender, guid);
	return sender;
end

---Scans byTime entries to find a sender whose bare name appears as a whole word in the message.
---@param message string
---@param sourceSender string? Full sender name or Name-Realm
---@return string? bareName
---@return string? sender Full sender name
---@return PlayerCacheEntryByTime? entry
function PlayerCache:ResolveEmoteSender(message, sourceSender)
	if not message or message == "" then return; end

	local sourceBare;
	if sourceSender and sourceSender ~= "" then
		sourceBare = sourceSender:match("^([^%-]+)");
	end

	for _, data in pairs(self.byTime) do
		local sender = data.sender;
		if sender then
			local bareName = sender:match("^([^%-]+)");

			-- Skip the emote's own sender (both bare and full comparison).
			if bareName and sender ~= sourceSender and bareName ~= sourceBare then
				local s, e = message:find(bareName, 1, true);
				if s then
					local before = message:sub(s - 1, s - 1);
					local after  = message:sub(e + 1, e + 1);

					-- Ensure full word match.
					if (before == "" or before:match("[%s%p]"))
					and (after == "" or after:match("[%s%p]")) then
						return bareName, sender, data;
					end
				end
			end
		end
	end
end

ED.PlayerCache = PlayerCache;
