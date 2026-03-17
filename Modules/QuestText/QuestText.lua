-- Copyright The Eavesdropper Authors
-- SPDX-License-Identifier: Apache-2.0

---@class EavesdropperQuestText
local QuestText = {};

-- We only handle customizations (beyond the OOC name) if there is an addon loaded that is supported.
local INSTALLED_QUEST_TEXT_ADDON;
local preferredName;

function QuestText.GetPlayerPreferredName()
	return preferredName;
end
ED.GetPreferredName = QuestText.GetPlayerPreferredName; -- TO-DO: Remove when Dialogue UI changes their calls.

function QuestText.RefreshPlayerPreferredName()
	preferredName = ED.Globals.player_character_name;
	if not INSTALLED_QUEST_TEXT_ADDON or not ED.MSP.IsEnabled() then
		return;
	end

	-- Request MSP data with a cache bust to make sure we get latest.
	local fullName, firstName = ED.MSP.TryGetMSPData(ED.Utils.GetUnitName(), ED.Globals.player_guid);
	local questTextNameDisplayMode = ED.Database:GetSetting("QuestTextNameDisplayMode");
	local useRPName = questTextNameDisplayMode ~= 3;

	if useRPName then
		if questTextNameDisplayMode == 2 and firstName then
			preferredName = firstName;
		elseif fullName then
			preferredName = fullName;
		end
	end
end

---@param questText string
function QuestText.SubstitutePlayerPreferredName(questText)
	if not INSTALLED_QUEST_TEXT_ADDON or ED.Database:GetSetting("QuestTextNameDisplayMode") == 3 then
		return questText;
	end

	if not preferredName then
		QuestText.RefreshPlayerPreferredName();
	end

	if not preferredName or not ED.Globals.player_character_name or ED.Globals.player_character_name == "" then
		return questText;
	end

	-- Escape certain characters that could be in names like - and . (Mary-Sue, J.W.).
	local escapedName = ED.Globals.player_character_name:gsub("([%(%)%.%%%+%-%*%?%[%^%$])", "%%%1");
	local result = questText:gsub(escapedName, preferredName);
	return result;
end
ED.ModifyPlayerNameInQuest = QuestText.SubstitutePlayerPreferredName; -- TO-DO: Remove when Dialogue UI changes their calls.

function QuestText.SupportedAddonsInstalled()
	return INSTALLED_QUEST_TEXT_ADDON;
end

local SUPPORTED_ADDONS = { "DialogueUI" };
function QuestText.Init()
	for _, name in ipairs(SUPPORTED_ADDONS) do
		if C_AddOns.IsAddOnLoaded(name) then
			INSTALLED_QUEST_TEXT_ADDON = name;
			break;
		end
	end
	-- We do not call RefreshPlayerPreferredName() here as it is called in MSP.Init() later
	-- or whenever the first SubstitutePlayerPreferredName call is by a supported addon.
end

ED.QuestText = QuestText;
