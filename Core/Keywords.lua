-- Copyright The Eavesdropper Authors
-- SPDX-License-Identifier: Apache-2.0

---@type EavesdropperConstants
local Constants = ED.Constants;

---@class EavesdropperKeywords
local Keywords = {};
Keywords.List = {};
Keywords.SortedList = {};

---Timestamp of the next allowed keyword notification.
---@type number
local notificationNextTime = 0;

---Rebuilds the keyword lookup table and sorted list from the HighlightKeywords setting.
---Applies token substitutions (<firstname>, <lastname>, <oocname>, <class>, <race>).
function Keywords:ParseList()
	if not ED or not ED.Database then return; end

	local highlightKeywords = ED.Database:GetSetting("HighlightKeywords");
	self.List = {};
	self.SortedList = {};

	if type(highlightKeywords) ~= "string" or highlightKeywords == "" then return; end

	-- Fetch MSP substitution values if MSP is enabled.
	local firstName, lastName, className, raceName;
	if ED.MSP.IsEnabled() then
		local _, fn, _, ln, cn, rn = ED.MSP.TryGetMSPData(ED.Globals.player_sender_name, ED.Globals.player_guid);
		firstName = fn;
		lastName  = ln;
		className = cn;
		raceName  = rn;
	end

	firstName = firstName or "";
	lastName  = lastName or "";
	className = className or "";
	raceName  = raceName or "";

	for word in highlightKeywords:gmatch("([^,]+)") do
		word = word:match("^%s*(.-)%s*$"); -- trim
		if word ~= "" then
			-- Substitutions
			word = word
				:gsub("<firstname>", firstName)
				:gsub("<lastname>",  lastName)
				:gsub("<oocname>",   ED.Globals.player_character_name)
				:gsub("<class>",     className)
				:gsub("<race>",      raceName);

			if word ~= "" then
				self.List[word:lower()] = true;
			end
		end
	end

	for kw in pairs(self.List) do
		self.SortedList[#self.SortedList + 1] = kw;
	end
	table.sort(self.SortedList, function(a, b) return #a > #b; end);
end

---Scans a chat message for keyword matches, wraps them in the highlight colour, and fires notifications.
---@param chatFrame table
---@param event string
---@param message string
---@param sender string
---@vararg any
---@return boolean? found True if keyword was found
---@return string? message Modified message with highlights
---@return string? sender Possibly updated sender
---@return any ... Remaining vararg values
function Keywords:HandleChecks(chatFrame, event, message, sender, ...) -- luacheck: no unused (chatFrame)
	if not message or not canaccessvalue(message) then return; end
	if not ED.Database:GetSetting("EnableKeywords") then return; end
	if ED.Utils.IsOwnPlayer(sender, event) then return; end
	if not self.SortedList or #self.SortedList == 0 then return; end

	-- Handle TRP NPC talk detection pattern.
	local msg = message;
	local trpNPCDetection = false;
	if event == "CHAT_MSG_EMOTE" and TRP3_API and message == " " then
		trpNPCDetection = true;
		msg = TRP3_API.chat.getNPCMessageName();
	end

	local enablePartial = ED.Database:GetSetting("EnablePartialKeywords");
	local originalLower = msg:lower();
	local found = false;

	-- Protect item/spell links from being modified by wrapping them in placeholders.
	local replaced = {};
	msg = msg:gsub("(|cff[0-9a-f]+|H[^|]+|h[^|]+|h|r)", function(link)
		replaced[#replaced + 1] = link;
		return Constants.KEYWORD_LINK_PLACEHOLDER .. #replaced .. Constants.KEYWORD_LINK_PLACEHOLDER;
	end);

	local highlightColor = ED.Database:GetSetting("HighlightColor");
	if type(highlightColor) ~= "table" then
		highlightColor = Constants.DEFAULT_HIGHLIGHT_COLOR;
	end

	local color = CreateColor(
		highlightColor.r or 0,
		highlightColor.g or 1,
		highlightColor.b or 0
	);

	local allMatches = {};
	-- Tracks character positions already consumed by a match, preventing a shorter keyword
	-- from matching inside a position already claimed by a longer one (e.g. "art" inside "party").
	local claimed = {};

	for _, kw in ipairs(self.SortedList) do
		local searchPos = 1;
		while searchPos <= #originalLower do
			local startPos, endPos = originalLower:find(kw, searchPos, true);
			if not startPos then break; end

			local matchOk = true;
			if not enablePartial then
				local beforeOk = startPos == 1
					or not originalLower:sub(startPos - 1, startPos - 1):match("[%w]");
				local afterOk = endPos == #originalLower
					or not originalLower:sub(endPos + 1, endPos + 1):match("[%w]");
				matchOk = beforeOk and afterOk;
			end

			if matchOk then
				local overlap = false;
				for pos = startPos, endPos do
					if claimed[pos] then
						overlap = true;
						break;
					end
				end

				if not overlap then
					found = true;
					allMatches[#allMatches + 1] = { startPos, endPos };
					for pos = startPos, endPos do
						claimed[pos] = true;
					end
				end
			end

			searchPos = endPos + 1;
		end
	end

	-- Apply replacements back-to-front so earlier positions are not shifted by later changes.
	table.sort(allMatches, function(a, b) return a[1] > b[1]; end);

	for _, m in ipairs(allMatches) do
		local raw = msg:sub(m[1], m[2]);
		local wrapped = ED.Utils.WrapTextInColor(raw, color);
		msg = msg:sub(1, m[1] - 1) .. wrapped .. msg:sub(m[2] + 1);
	end

	if found then
		local now = GetTime();
		if now > notificationNextTime then
			notificationNextTime = now + Constants.KEYWORDS_NOTIFICATION_CD;

			if ED.Database:GetSetting("NotificationKeywordsSound") then
				ED.Notifications:PlayAlertSound(ED.Enums.NOTIFICATIONS_TYPE.KEYWORDS);
			end

			if ED.Database:GetSetting("NotificationKeywordsFlashTaskbar") then
				ED.Notifications:FlashTaskbar();
			end
		end

		-- Restore original links from their placeholders.
		msg = msg:gsub(
			Constants.KEYWORD_LINK_PLACEHOLDER .. "(%d+)" .. Constants.KEYWORD_LINK_PLACEHOLDER,
			function(idx)
				return replaced[tonumber(idx)];
			end
		);

		if trpNPCDetection then
			-- Safeguard for TRP versions prior to 3.3.3.
			if TRP3_API.chat.setNPCMessageName then
				TRP3_API.chat.setNPCMessageName(msg);
			end
			return false, message, sender, ...;
		end

		return false, msg, sender, ...;
	end
end

ED.Keywords = Keywords;
