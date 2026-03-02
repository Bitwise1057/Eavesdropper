-- Copyright The Eavesdropper Authors
-- SPDX-License-Identifier: Apache-2.0

---@type EavesdropperConstants
local Constants = ED.Constants;

---@type EavesdropperEnums
local Enums = ED.Enums;

---@class EavesdropperMagnifier
local Magnifier = {};

local magnifiedName = nil;
local magnifiedGUID = nil;
local clearTimerToken = nil;
Magnifier.Frame = nil;

local function tickerCallback()
	if ED.Frame then
		ED.Frame:UpdateTarget();
	end
end

local function createTicker(self, handleField, interval, callback)
	if not self[handleField] then
		self[handleField] = C_Timer.NewTicker(interval, callback);
	end
end

local function stopTicker(self, handleField)
	if self[handleField] then
		self[handleField]:Cancel();
		self[handleField] = nil;
	end
end

---StartUpdateCheck begins polling via OnUpdate
---@return nil
function Magnifier:StartUpdateCheck()
	if not self.Frame or self.Frame:GetScript("OnUpdate") then return; end
	self.Frame:SetScript("OnUpdate", function()
		self:HandleUpdate(Enums.MAGNIFIER_REASON.MOUSEOVER);
	end);
end

---StopUpdateCheck stops OnUpdate polling
---@return nil
function Magnifier:StopUpdateCheck()
	if self.Frame then
		self.Frame:SetScript("OnUpdate", nil);
	end
end

---GetMagnified Returns current magnified unit.
---@return string? name
---@return string? guid
function Magnifier:GetMagnified()
	return magnifiedName, magnifiedGUID;
end

---OnMagnifiedChanged Notifies UI of magnifier change.
---@param reason EavesdropperMagnifierReason?
---@return nil
function Magnifier:OnMagnifiedChanged(reason) -- luacheck: no unused (reason)
	-- Bail out when there's secrets involved (PvP or other situations we don't support).
	if not canaccessvalue(magnifiedGUID) or not canaccessvalue(self.lastNotifiedGUID) then
		return;
	end

	-- Skip if magnified target hasn't changed (except when cleared)
	local isUnchanged = magnifiedGUID ~= nil
		and magnifiedGUID == self.lastNotifiedGUID
		and magnifiedName == self.lastNotifiedName;
	if isUnchanged then
		return;
	end

	if clearTimerToken then
		clearTimerToken:Cancel();
		clearTimerToken = nil;
	end

	-- Calculate delay (this avoids target flicks in certain situations)
	local delay = magnifiedGUID and Constants.MAGNIFIER_CHANGE_THROTTLE or Constants.MAGNIFIER_NIL_THROTTLE;

	self.lastNotifiedGUID = magnifiedGUID;
	self.lastNotifiedName = magnifiedName;
	clearTimerToken = C_Timer.NewTimer(delay, function()
		clearTimerToken = nil;
		ED.Debug:Print("Magnifier:OnMagnifiedChanged() -", magnifiedName);
		if ED and ED.Frame then
			ED.Frame:UpdateMagnifier();
		end
	end);
end

---HandleUpdate polls the current target/mouseover unit.
---@param reason EavesdropperMagnifierReason?
---@return nil
function Magnifier:HandleUpdate(reason) -- luacheck: no unused (reason)
	if not ED or not ED.Database then return; end
	if not canaccessvalue(magnifiedGUID) then return; end

	local targetPriority = ED.Database:GetSetting("TargetPriority");
	if not targetPriority then return; end

	local focusTarget = ED.Database:GetSetting("FocusTarget");
	local entry = Enums.TARGET_PRIORITY_UNIT_MAP[targetPriority];
	local priority = entry and entry.priority;
	local secondary = entry and entry.secondary;

	local focus;
	if focusTarget ~= Enums.FOCUS_TARGET.IGNORE and targetPriority ~= Enums.TARGET_PRIORITY.TARGET_ONLY and targetPriority ~= Enums.TARGET_PRIORITY.MOUSEOVER_ONLY then
		focus = "focus";
	end

	local unit;
	if focusTarget == Enums.FOCUS_TARGET.OVERRIDE then
		unit = (focus and UnitExists(focus) and focus)
			or (priority and UnitExists(priority) and priority)
			or (secondary and UnitExists(secondary) and secondary);
	elseif focusTarget == Enums.FOCUS_TARGET.FALLBACK then
		unit = (priority and UnitExists(priority) and priority)
			or (secondary and UnitExists(secondary) and secondary)
			or (focus and UnitExists(focus) and focus);
	elseif focusTarget == Enums.FOCUS_TARGET.IGNORE then
		unit = (priority and UnitExists(priority) and priority)
			or (secondary and UnitExists(secondary) and secondary);
	end

	-- Determine polling behavior
	local target = UnitExists("target");
	local mouseover = UnitExists("mouseover");
	local polling = false;

	if targetPriority == Enums.TARGET_PRIORITY.TARGET_ONLY then
		polling = false; -- never poll, only track target
	elseif targetPriority == Enums.TARGET_PRIORITY.MOUSEOVER_ONLY then
		polling = mouseover; -- poll if mouseover exists
	elseif targetPriority == Enums.TARGET_PRIORITY.PRIORITIZE_TARGET then
		polling = not target and mouseover; -- poll only if no target but mouseover exists
	elseif targetPriority == Enums.TARGET_PRIORITY.PRIORITIZE_MOUSEOVER then
		polling = mouseover; -- poll whenever mouseover exists
	end

	local unitName, unitGUID;
	if unit then
		if UnitIsPlayer(unit) then
			unitName = ED.Utils.GetUnitName(unit);
			unitGUID = UnitGUID(unit);
		elseif UnitOwnerGUID(unit) and ED.Database:GetSetting("CompanionSupport") then
			-- Handle pets/companions
			unitGUID = UnitOwnerGUID(unit);
			unitName = nil;
		end
	end

	if unitGUID and not canaccessvalue(unitGUID) then
		return;
	end

	if polling then
		self:StartUpdateCheck();
	else
		self:StopUpdateCheck();
	end

	-- Start Eavesdropper Update (to refresh chat timestamps etc) if unit is found.
	if unitGUID then
		createTicker(self, "EavesdropperUpdate", Constants.CHAT_UPDATE_THROTTLE_DEFAULT, tickerCallback);
	else
		stopTicker(self, "EavesdropperUpdate");
	end

	-- If same unit while polling, we're already matched.
	if polling and magnifiedGUID == unitGUID then
		return;
	end

	-- Update magnified state
	magnifiedName = unitName;
	magnifiedGUID = unitGUID;
	self:OnMagnifiedChanged(reason);
end

---Setup creates the internal frame for polling
---@return nil
function Magnifier:Setup()
	if Magnifier.Frame then return; end
	Magnifier.Frame = CreateFrame("Frame");
	Magnifier.Frame:Show();
end

ED.Magnifier = Magnifier;
