-- Copyright The Eavesdropper Authors
-- SPDX-License-Identifier: Apache-2.0

---@class EavesdropperNotifications
local Notifications = {};

---@type number
local notificationCd = 0;

local SharedMedia = LibStub("LibSharedMedia-3.0");

---@type table<string, {file: string, path: string}>
local soundCache = {};

---Flashes the WoW client icon on the taskbar.
function Notifications:FlashTaskbar()
	FlashClientIcon();
end

---Plays the configured alert sound for the given notification type, subject to a throttle.
---@param notifType EavesdropperNotificationsType
function Notifications:PlayAlertSound(notifType)
	local now = GetTime();
	local throttle = ED.Database:GetSetting("NotificationThrottle");

	if now < notificationCd + throttle then return; end
	notificationCd = now;

	local key = ED.Enums.NOTIFICATIONS_TYPE_SOUND_KEYS[notifType];
	if not key then return; end

	local soundFile = ED.Database:GetSetting(key);
	if not soundFile or soundFile == "" then return; end

	-- Refresh the cached path only if the sound file setting has changed.
	if not soundCache[key] or soundCache[key].file ~= soundFile then
		local soundPath = SharedMedia:Fetch("sound", soundFile);
		soundCache[key] = { file = soundFile, path = soundPath };
	end

	local path = soundCache[key].path;
	if path then
		PlaySoundFile(path, "Master");
	end
end

ED.Notifications = Notifications;
