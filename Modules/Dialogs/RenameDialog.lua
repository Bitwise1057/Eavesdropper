-- Copyright The Eavesdropper Authors
-- SPDX-License-Identifier: Apache-2.0

---@class EavesdropperRenameDialog
local RenameDialog = {};

local MaxProfileNameLength = 32;

---Attempts to rename the profile from oldName to the trimmed text in the edit box.
---@param oldName string?
---@param newName string
---@return boolean success
local function tryRename(oldName, newName)
	local trimmed = string.trim(newName);
	if not oldName or trimmed == "" or trimmed == oldName then return false; end
	if ED.Database:ProfileExists(trimmed) then return false; end
	ED.Database:RenameProfile(oldName, trimmed);
	return true;
end

StaticPopupDialogs["EAVESDROPPER_RENAME_PROFILE"] = {
	button1 = ACCEPT,
	button2 = CANCEL,
	hasEditBox = true,
	maxLetters = MaxProfileNameLength,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
	OnAccept = function(self, data)
		tryRename(data and data.oldName, self.EditBox:GetText());
	end,
	OnShow = function(self, data)
		local button1 = _G[self:GetName() .. "Button1"];
		if button1 then
			button1:Disable();
		end
		local currentName = data and data.oldName or "";
		self.EditBox:SetText(currentName);
		self.EditBox:HighlightText();
		self.EditBox:SetFocus();
	end,
	EditBoxOnTextChanged = function(self, data)
		local popup = self:GetParent();
		local button1 = _G[popup:GetName() .. "Button1"];
		if not button1 then return; end

		local newName = string.trim(self:GetText());
		local currentName = data and data.oldName or "";
		local isDuplicate = ED.Database:ProfileExists(newName);
		local isSame = newName == currentName;

		button1:SetEnabled(newName ~= "" and not isDuplicate and not isSame);
	end,
	EditBoxOnEscapePressed = function(self)
		StaticPopup_Hide("EAVESDROPPER_RENAME_PROFILE");
	end,
	EditBoxOnEnterPressed = function(self, data)
		if tryRename(data and data.oldName, self:GetText()) then
			StaticPopup_Hide("EAVESDROPPER_RENAME_PROFILE");
		end
	end,
};

ED.RenameDialog = RenameDialog;
