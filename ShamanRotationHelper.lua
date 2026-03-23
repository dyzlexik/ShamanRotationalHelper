SRH = {}

SRH.defaults = {
	enabled = true,
	unlocked = false,
	showFlameShock = true,
	showMoltenBlast = true,
	onlyChainLightningOnClearcasting = true,
	maintainShield = true,
	shieldSpell = "Water Shield",
	moltenBlastStartRemaining = 6,
	moltenBlastEndRemaining = 2,
	showElementalMastery = true,
	showBloodFury = true,
	mainPosition = { x = 0, y = 220 },
	emPosition = { x = -72, y = 220 },
	bfPosition = { x = 72, y = 220 },
}

SRH.spells = {
	flameShock = "Flame Shock",
	moltenBlast = "Molten Blast",
	chainLightning = "Chain Lightning",
	waterShield = "Water Shield",
	lightningBolt = "Lightning Bolt",
	elementalMastery = "Elemental Mastery",
	bloodFury = "Blood Fury",
}

SRH.buffNames = {
	clearcasting = "Clearcasting",
	waterShield = "Water Shield",
	lightningShield = "Lightning Shield",
	earthShield = "Earth Shield",
}

SRH.buffTextures = {}
SRH.spellBook = {}
SRH.targetDebuffs = {}
SRH.updateThrottle = 0
SRH.pendingShock = nil
SRH.pendingMoltenBlast = nil
SRH.isMounted = false
SRH.supportsExtendedUnitDebuff = nil
SRH.hooksInstalled = false
SRH.playerGuid = nil
SRH.fireImmuneTargets = {}
SRH.skipMoltenBlastUntilExpire = {}

local function copyDefaults(src)
	local dst = {}
	for key, value in pairs(src) do
		if type(value) == "table" then
			dst[key] = copyDefaults(value)
		else
			dst[key] = value
		end
	end
	return dst
end

local function mergeDefaults(dst, src)
	for key, value in pairs(src) do
		if type(value) == "table" then
			if type(dst[key]) ~= "table" then
				dst[key] = {}
			end
			mergeDefaults(dst[key], value)
		elseif dst[key] == nil then
			dst[key] = value
		end
	end
end

local function round(num)
	return math.floor(num + 0.5)
end

local function tableLength(tbl)
	local count = 0
	for _ in pairs(tbl) do
		count = count + 1
	end
	return count
end

function SRH:Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99SRH|r: " .. msg)
end

function SRH:OnLoad()
	this:RegisterEvent("ADDON_LOADED")
	this:RegisterEvent("PLAYER_ENTERING_WORLD")
	this:RegisterEvent("PLAYER_REGEN_DISABLED")
	this:RegisterEvent("PLAYER_REGEN_ENABLED")
	this:RegisterEvent("PLAYER_TARGET_CHANGED")
	this:RegisterEvent("PLAYER_AURAS_CHANGED")
	this:RegisterEvent("SPELLS_CHANGED")
	this:RegisterEvent("SPELLCAST_START")
	this:RegisterEvent("SPELLCAST_STOP")
	this:RegisterEvent("SPELLCAST_FAILED")
	this:RegisterEvent("SPELLCAST_INTERRUPTED")
	this:RegisterEvent("CHAT_MSG_SPELL_SELF_DAMAGE")
	this:RegisterEvent("CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE")
	this:RegisterEvent("CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE")
	if SpellInfo then
		this:RegisterEvent("UNIT_CASTEVENT")
	end

	SLASH_SRH1 = "/srh"
	SlashCmdList["SRH"] = function(msg)
		SRH:HandleSlash(msg)
	end
end

function SRH:OnEvent(event)
	if event == "ADDON_LOADED" then
		if arg1 == "ShamanRotationHelper" then
			self:Initialize()
		end
	elseif event == "PLAYER_ENTERING_WORLD" then
		local _, playerGuid = UnitExists("player")
		self.playerGuid = playerGuid
		self:RefreshSpells()
		self:RefreshVisuals()
	elseif event == "SPELLS_CHANGED" then
		self:RefreshSpells()
		self:RefreshVisuals()
	elseif event == "PLAYER_TARGET_CHANGED" then
		self:CleanupDebuffCache()
		self:RefreshVisuals()
	elseif event == "PLAYER_AURAS_CHANGED" then
		self:RefreshVisuals()
	elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		self:RefreshVisuals()
	elseif event == "SPELLCAST_START" then
		self:OnSpellcastStart(arg1)
	elseif event == "SPELLCAST_STOP" then
		self:OnSpellcastStop()
	elseif event == "SPELLCAST_FAILED" or event == "SPELLCAST_INTERRUPTED" then
		self.pendingShock = nil
	elseif event == "CHAT_MSG_SPELL_SELF_DAMAGE" or event == "CHAT_MSG_SPELL_HOSTILEPLAYER_DAMAGE" or event == "CHAT_MSG_SPELL_CREATURE_VS_SELF_DAMAGE" then
		self:HandleCombatLog(arg1)
	elseif event == "UNIT_CASTEVENT" then
		self:HandleUnitCastEvent(arg1, arg2, arg3, arg4, arg5)
	end
end

function SRH:OnUpdate(elapsed)
	self.updateThrottle = self.updateThrottle + elapsed
	if self.updateThrottle < 0.05 then
		return
	end
	self.updateThrottle = 0
	self:CleanupDebuffCache()
	self:RefreshVisuals()
end

function SRH:Initialize()
	if not SRH_DB then
		SRH_DB = copyDefaults(self.defaults)
	else
		mergeDefaults(SRH_DB, self.defaults)
	end

	if SRH_DB.showClearcastingChainLightning ~= nil and SRH_DB.onlyChainLightningOnClearcasting == nil then
		SRH_DB.onlyChainLightningOnClearcasting = SRH_DB.showClearcastingChainLightning and true or false
	end

	if SRH_DB.showWaterShield ~= nil and SRH_DB.maintainShield == nil then
		SRH_DB.maintainShield = SRH_DB.showWaterShield and true or false
	end

	if not SRH_DB.shieldSpell then
		SRH_DB.shieldSpell = "Water Shield"
	end

	self.db = SRH_DB
	self:CreateScannerTooltip()
	self:CreateFrames()
	self:CreateConfigFrame()
	self:RefreshSpells()
	self:InstallHooks()
	self:ApplyLockState()
	self:RefreshVisuals()
end

function SRH:CreateScannerTooltip()
	if self.scanTooltip then
		return
	end

	local tooltip = CreateFrame("GameTooltip", "SRHScanTooltip", UIParent, "GameTooltipTemplate")
	tooltip:SetOwner(UIParent, "ANCHOR_NONE")
	self.scanTooltip = tooltip
end

function SRH:InstallHooks()
	if self.hooksInstalled then
		return
	end

	self.hooksInstalled = true
	self.originalUseAction = UseAction
	self.originalCastSpell = CastSpell
	self.originalCastSpellByName = CastSpellByName

	UseAction = function(id, book, onself)
		SRH:HookUseAction(id)
		SRH.originalUseAction(id, book, onself)
	end

	CastSpell = function(id, book)
		SRH:HookCastSpell(id, book)
		SRH.originalCastSpell(id, book)
	end

	CastSpellByName = function(spellName, onself)
		SRH:HookCastSpellByName(spellName)
		SRH.originalCastSpellByName(spellName, onself)
	end
end

function SRH:NormalizeSpellName(spellName)
	if not spellName then
		return nil
	end

	spellName = string.gsub(spellName, "%s*%(.+%)", "")
	return spellName
end

function SRH:MarkPendingShock(spellName)
	spellName = self:NormalizeSpellName(spellName)
	if spellName ~= self.spells.flameShock then
		return
	end

	local key = self:GetTargetKey()
	if not key then
		return
	end

	self.pendingShock = {
		targetKey = key,
		spell = spellName,
		startedAt = GetTime(),
	}
end

function SRH:HookUseAction(id)
	if not id or not self.scanTooltip then
		return
	end

	self.scanTooltip:SetAction(id)
	local left = getglobal("SRHScanTooltipTextLeft1")
	if left then
		self:MarkPendingShock(left:GetText())
	end
end

function SRH:HookCastSpell(id, book)
	local spellName = GetSpellName(id, book or BOOKTYPE_SPELL)
	self:MarkPendingShock(spellName)
end

function SRH:HookCastSpellByName(spellName)
	self:MarkPendingShock(spellName)
end

function SRH:CreateFrames()
	if self.frames then
		return
	end

	self.frames = {}
	self.frames.main = self:CreateIconFrame("SRH_RotationIcon", 64, self.db.mainPosition, "Next Spell")
	self.frames.em = self:CreateIconFrame("SRH_ElementalMasteryIcon", 40, self.db.emPosition, "Elemental Mastery")
	self.frames.bf = self:CreateIconFrame("SRH_BloodFuryIcon", 40, self.db.bfPosition, "Blood Fury")
end

function SRH:CreateIconFrame(name, size, position, fallbackLabel)
	local frame = CreateFrame("Button", name, UIParent)
	frame:SetWidth(size)
	frame:SetHeight(size)
	frame:SetMovable(true)
	frame:RegisterForDrag("LeftButton")
	frame:Hide()

	frame.icon = frame:CreateTexture(nil, "ARTWORK")
	frame.icon:SetAllPoints(frame)

	frame.border = frame:CreateTexture(nil, "OVERLAY")
	frame.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
	frame.border:SetAllPoints(frame)

	frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -2)
	frame.label:SetText(fallbackLabel)

	frame.cooldown = CreateFrame("Model", nil, frame, "CooldownFrameTemplate")
	frame.cooldown:SetAllPoints(frame)

	frame:SetScript("OnDragStart", function()
		if SRH.db.unlocked then
			this:StartMoving()
		end
	end)

	frame:SetScript("OnDragStop", function()
		this:StopMovingOrSizing()
		SRH:SaveFramePosition(this)
	end)

	frame:SetScript("OnEnter", function()
		if this.spellName then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetSpell(this.spellBookIndex or 1, BOOKTYPE_SPELL)
			GameTooltip:Show()
		elseif this.tooltipText then
			GameTooltip:SetOwner(this, "ANCHOR_RIGHT")
			GameTooltip:SetText(this.tooltipText)
			GameTooltip:Show()
		end
	end)

	frame:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	frame:ClearAllPoints()
	frame:SetPoint("CENTER", UIParent, "CENTER", position.x, position.y)
	return frame
end

function SRH:CreateConfigFrame()
	if self.configFrame then
		return
	end

	local frame = CreateFrame("Frame", "SRH_ConfigFrame", UIParent)
	frame:SetWidth(300)
	frame:SetHeight(390)
	frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function() this:StartMoving() end)
	frame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 5, right = 5, top = 5, bottom = 5 }
	})
	frame:SetBackdropColor(0, 0, 0, 0.9)
	frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
	frame:Hide()

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	title:SetPoint("TOP", frame, "TOP", 0, -14)
	title:SetText("Shaman Rotation Helper")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -4, -4)

	local options = {
		{ key = "enabled", label = "Enable addon" },
		{ key = "showFlameShock", label = "Use Flame Shock opener" },
		{ key = "showMoltenBlast", label = "Use Molten Blast refresh" },
		{ key = "onlyChainLightningOnClearcasting", label = "Only use Chain Lightning on Clearcasting" },
		{ key = "maintainShield", label = "Maintain Shield" },
		{ key = "showElementalMastery", label = "Show Elemental Mastery reminder" },
		{ key = "showBloodFury", label = "Show Blood Fury reminder" },
	}

	local previous = nil
	for index, option in ipairs(options) do
		local checkbox = CreateFrame("CheckButton", "SRH_Config_" .. option.key, frame, "UICheckButtonTemplate")
		if index == 1 then
			checkbox:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -44)
		else
			checkbox:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 0, -14)
		end
		getglobal(checkbox:GetName() .. "Text"):SetText(option.label)
		checkbox:SetScript("OnClick", function()
			SRH.db[option.key] = this:GetChecked() and true or false
			SRH:RefreshVisuals()
		end)
		frame[option.key] = checkbox
		previous = checkbox
	end

	local shieldLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	shieldLabel:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", 8, -20)
	shieldLabel:SetText("Shield Spell")

	local shieldDropdown = CreateFrame("Frame", "SRH_ShieldDropdown", frame, "UIDropDownMenuTemplate")
	shieldDropdown:SetPoint("TOPLEFT", shieldLabel, "BOTTOMLEFT", -18, -6)
	UIDropDownMenu_SetWidth(140, shieldDropdown)
	UIDropDownMenu_Initialize(shieldDropdown, function()
		local info = {}
		info.text = "Water Shield"
		info.func = function()
			SRH.db.shieldSpell = "Water Shield"
			UIDropDownMenu_SetSelectedName(SRH_ShieldDropdown, "Water Shield")
			SRH:RefreshVisuals()
		end
		UIDropDownMenu_AddButton(info)

		info = {}
		info.text = "Lightning Shield"
		info.func = function()
			SRH.db.shieldSpell = "Lightning Shield"
			UIDropDownMenu_SetSelectedName(SRH_ShieldDropdown, "Lightning Shield")
			SRH:RefreshVisuals()
		end
		UIDropDownMenu_AddButton(info)

		info = {}
		info.text = "Earth Shield"
		info.func = function()
			SRH.db.shieldSpell = "Earth Shield"
			UIDropDownMenu_SetSelectedName(SRH_ShieldDropdown, "Earth Shield")
			SRH:RefreshVisuals()
		end
		UIDropDownMenu_AddButton(info)
	end)
	frame.shieldDropdown = shieldDropdown

	local unlock = CreateFrame("Button", "SRH_ConfigUnlockButton", frame, "GameMenuButtonTemplate")
	unlock:SetWidth(120)
	unlock:SetHeight(22)
	unlock:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 18, 18)
	unlock:SetText("Unlock Icons")
	unlock:SetScript("OnClick", function()
		SRH.db.unlocked = not SRH.db.unlocked
		SRH:ApplyLockState()
		SRH:SyncConfig()
	end)

	local reset = CreateFrame("Button", "SRH_ConfigResetButton", frame, "GameMenuButtonTemplate")
	reset:SetWidth(120)
	reset:SetHeight(22)
	reset:SetPoint("LEFT", unlock, "RIGHT", 16, 0)
	reset:SetText("Reset Positions")
	reset:SetScript("OnClick", function()
		SRH:ResetPositions()
	end)

	self.configFrame = frame
	self:SyncConfig()
end

function SRH:SyncConfig()
	if not self.configFrame then
		return
	end

	local options = {
		"enabled",
		"showFlameShock",
		"showMoltenBlast",
		"onlyChainLightningOnClearcasting",
		"maintainShield",
		"showElementalMastery",
		"showBloodFury",
	}

	for _, key in ipairs(options) do
		self.configFrame[key]:SetChecked(self.db[key] and 1 or nil)
	end

	if self.db.unlocked then
		SRH_ConfigUnlockButton:SetText("Lock Icons")
	else
		SRH_ConfigUnlockButton:SetText("Unlock Icons")
	end

	if self.configFrame.shieldDropdown then
		UIDropDownMenu_SetSelectedName(self.configFrame.shieldDropdown, self.db.shieldSpell)
	end
end

function SRH:HandleSlash(msg)
	msg = string.lower(string.gsub(msg or "", "^%s*(.-)%s*$", "%1"))

	if msg == "config" or msg == "" then
		if self.configFrame:IsShown() then
			self.configFrame:Hide()
		else
			self:SyncConfig()
			self.configFrame:Show()
		end
	elseif msg == "unlock" then
		self.db.unlocked = true
		self:ApplyLockState()
		self:Print("Icons unlocked.")
	elseif msg == "lock" then
		self.db.unlocked = false
		self:ApplyLockState()
		self:Print("Icons locked.")
	elseif msg == "reset" then
		self:ResetPositions()
		self:Print("Positions reset.")
	elseif msg == "test" then
		self:ShowTestIcons()
	else
		self:Print("Commands: /srh, /srh config, /srh unlock, /srh lock, /srh reset, /srh test")
	end
end

function SRH:ApplyLockState()
	if not self.frames then
		return
	end

	for _, frame in pairs(self.frames) do
		frame:EnableMouse(self.db.unlocked and true or false)
	end
end

function SRH:SaveFramePosition(frame)
	local x, y = frame:GetCenter()
	local cx, cy = UIParent:GetCenter()
	local position = {
		x = round(x - cx),
		y = round(y - cy),
	}

	if frame == self.frames.main then
		self.db.mainPosition = position
	elseif frame == self.frames.em then
		self.db.emPosition = position
	elseif frame == self.frames.bf then
		self.db.bfPosition = position
	end
end

function SRH:ResetPositions()
	self.db.mainPosition = copyDefaults(self.defaults.mainPosition)
	self.db.emPosition = copyDefaults(self.defaults.emPosition)
	self.db.bfPosition = copyDefaults(self.defaults.bfPosition)

	self.frames.main:ClearAllPoints()
	self.frames.main:SetPoint("CENTER", UIParent, "CENTER", self.db.mainPosition.x, self.db.mainPosition.y)
	self.frames.em:ClearAllPoints()
	self.frames.em:SetPoint("CENTER", UIParent, "CENTER", self.db.emPosition.x, self.db.emPosition.y)
	self.frames.bf:ClearAllPoints()
	self.frames.bf:SetPoint("CENTER", UIParent, "CENTER", self.db.bfPosition.x, self.db.bfPosition.y)
end

function SRH:RefreshSpells()
	self.spellBook = {}
	for tab = 1, 8 do
		local _, _, offset, numSpells = GetSpellTabInfo(tab)
		if not offset then
			break
		end

		for i = offset + 1, offset + numSpells do
			local spellName, spellRank = GetSpellName(i, BOOKTYPE_SPELL)
			if spellName then
				self.spellBook[spellName] = {
					index = i,
					rank = spellRank,
					texture = GetSpellTexture(i, BOOKTYPE_SPELL),
				}
			end
		end
	end

	for key, spellName in pairs(self.spells) do
		if self.spellBook[spellName] then
			self.spells[key .. "Texture"] = self.spellBook[spellName].texture
		end
	end

	self.buffTextures.clearcasting = self:GetBuffTextureBySpellName(self.buffNames.clearcasting)
	self.buffTextures.waterShield = self:GetBuffTextureBySpellName(self.buffNames.waterShield)
	self.buffTextures.lightningShield = self:GetBuffTextureBySpellName(self.buffNames.lightningShield)
	self.buffTextures.earthShield = self:GetBuffTextureBySpellName(self.buffNames.earthShield)
	self.buffTextures.flameShock = self:GetBuffTextureBySpellName(self.spells.flameShock)
end

function SRH:GetBuffTextureBySpellName(spellName)
	local spell = self.spellBook[spellName]
	if spell then
		return spell.texture
	end
	return nil
end

function SRH:GetSpellCooldownRemaining(spellName)
	local spell = self.spellBook[spellName]
	if not spell then
		return nil
	end

	local start, duration = GetSpellCooldown(spell.index, BOOKTYPE_SPELL)
	if not start or not duration then
		return nil
	end
	if start == 0 or duration == 0 then
		return 0
	end
	return math.max(0, (start + duration) - GetTime())
end

function SRH:HasPlayerBuffByTexture(texture)
	if not texture then
		return false
	end

	for i = 0, 31 do
		local buffIndex = GetPlayerBuff(i, "HELPFUL|PASSIVE")
		if buffIndex and buffIndex >= 0 then
			if GetPlayerBuffTexture(buffIndex) == texture then
				return true
			end
		else
			break
		end
	end
	return false
end

function SRH:HasPlayerBuffByName(buffName)
	if not buffName then
		return false
	end

	if GetPlayerBuffID and SpellInfo then
		for i = 0, 40 do
			local buffID = GetPlayerBuffID(i)
			if not buffID then
				break
			end

			local name = SpellInfo(buffID)
			if name == buffName or (name and string.find(string.lower(name), string.lower(buffName), 1, true)) then
				return true
			end
		end
	end

	for i = 0, 31 do
		local buffIndex = GetPlayerBuff(i, "HELPFUL|PASSIVE")
		if buffIndex and buffIndex >= 0 then
			local texture = GetPlayerBuffTexture(buffIndex)
			if texture and self.buffTextures.clearcasting and texture == self.buffTextures.clearcasting and buffName == self.buffNames.clearcasting then
				return true
			end
		else
			break
		end
	end

	return false
end

function SRH:GetPlayerBuffState(buffName, expectedTexture)
	local found = false
	local applications = 0

	for i = 0, 31 do
		local buffIndex = GetPlayerBuff(i, "HELPFUL|PASSIVE")
		if buffIndex and buffIndex >= 0 then
			local texture = GetPlayerBuffTexture(buffIndex)
			local count = GetPlayerBuffApplications and GetPlayerBuffApplications(buffIndex) or 0
			if expectedTexture and texture == expectedTexture then
				found = true
				applications = count or 0
				break
			end
		else
			break
		end
	end

	if GetPlayerBuffID and SpellInfo then
		for i = 0, 40 do
			local buffID = GetPlayerBuffID(i)
			if not buffID then
				break
			end

			local name = SpellInfo(buffID)
			if name == buffName or (name and string.find(string.lower(name), string.lower(buffName), 1, true)) then
				found = true
				if applications == 0 then
					applications = 1
				end
				break
			end
		end
	end

	return found, applications
end

function SRH:IsMounted()
	for i = 0, 31 do
		local buffIndex = GetPlayerBuff(i, "HELPFUL|PASSIVE")
		if buffIndex and buffIndex >= 0 then
			local texture = GetPlayerBuffTexture(buffIndex)
			if texture and string.find(string.lower(texture), "mount") then
				return true
			end
		else
			break
		end
	end
	return false
end

function SRH:IsRotationVisible()
	if not self.db.enabled then
		return false
	end
	if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
		return false
	end
	if self:IsMounted() then
		return false
	end
	if not UnitExists("target") then
		return false
	end
	if UnitIsDead("target") then
		return false
	end
	if UnitIsFriend and UnitIsFriend("player", "target") then
		return false
	end
	if UnitCanAttack and not UnitCanAttack("player", "target") and not UnitCanAttack("target", "player") then
		return false
	end
	return true
end

function SRH:GetTargetKey()
	if not UnitExists("target") then
		return nil
	end

	local _, guid = UnitExists("target")
	if guid then
		return guid
	end

	if UnitGUID then
		local guid = UnitGUID("target")
		if guid then
			return guid
		end
	end

	local name = UnitName("target") or "unknown"
	local level = UnitLevel("target") or -1
	local health = UnitHealthMax("target") or -1
	return name .. ":" .. level .. ":" .. health
end

function SRH:GetTargetFlameShockState()
	local key = self:GetTargetKey()
	if not key then
		return nil
	end

	local record = self.targetDebuffs[key]
	if not record then
		return nil
	end

	local now = GetTime()
	if record.appliedAt and not record.expiresAt then
		record.expiresAt = record.appliedAt + 15
	end
	if record.expiresAt and not record.appliedAt then
		record.appliedAt = record.expiresAt - 15
	end

	local remaining = (record.expiresAt or now) - now
	if remaining <= 0 then
		self.targetDebuffs[key] = nil
		return nil
	end

	return record, remaining
end

function SRH:IsCurrentTargetFireImmune()
	local key = self:GetTargetKey()
	if not key then
		return false
	end
	return self.fireImmuneTargets[key] and true or false
end

function SRH:MarkTargetFireImmune(targetGuid)
	if not targetGuid then
		return
	end
	self.fireImmuneTargets[targetGuid] = true
	self.targetDebuffs[targetGuid] = nil
	if self.pendingShock and self.pendingShock.targetKey == targetGuid then
		self.pendingShock = nil
	end
	if self.pendingMoltenBlast and self.pendingMoltenBlast.targetGuid == targetGuid then
		self.pendingMoltenBlast = nil
	end
	self.skipMoltenBlastUntilExpire[targetGuid] = nil
end

function SRH:RefreshFlameShockFromMoltenBlast(targetGuid)
	if not targetGuid or self.fireImmuneTargets[targetGuid] then
		return
	end

	self.targetDebuffs[targetGuid] = {
		name = self.spells.flameShock,
		expiresAt = GetTime() + 15,
		appliedAt = GetTime(),
		ownedByPlayer = true,
		refreshedByMoltenBlast = true,
	}
	self.skipMoltenBlastUntilExpire[targetGuid] = nil
end

function SRH:GetGuidDebuffInfo(guid, index)
	if not guid then
		return nil
	end

	local texture, applications, debuffType, spellID = UnitDebuff(guid, index)
	if not spellID and not texture then
		return nil
	end

	local name, rank, spellTexture = nil, nil, texture
	if spellID and SpellInfo then
		name, rank, spellTexture = SpellInfo(spellID)
	end

	return {
		name = name,
		rank = rank,
		icon = texture or spellTexture,
		count = applications,
		debuffType = debuffType,
		spellID = spellID,
	}
end

function SRH:GetUnitDebuffInfo(unit, index)
	local name, rank, icon, count, debuffType, duration, expirationTime, unitCaster = UnitDebuff(unit, index)

	if type(name) == "string" or duration ~= nil or expirationTime ~= nil or unitCaster ~= nil then
		self.supportsExtendedUnitDebuff = true
		return {
			name = name,
			rank = rank,
			icon = icon,
			count = count,
			debuffType = debuffType,
			duration = duration,
			expirationTime = expirationTime,
			unitCaster = unitCaster,
		}
	end

	local texture, applications, dispelType, debuffID = UnitDebuff(unit, index)
	if texture then
		if self.supportsExtendedUnitDebuff == nil then
			self.supportsExtendedUnitDebuff = false
		end
		return {
			name = nil,
			icon = texture,
			count = applications,
			debuffType = dispelType,
			debuffID = debuffID,
		}
	end

	return nil
end

function SRH:ScanTargetFlameShock()
	local key = self:GetTargetKey()
	if not key then
		return nil
	end
	local found

	for i = 1, 64 do
		local debuff = nil
		if SpellInfo then
			debuff = self:GetGuidDebuffInfo(key, i)
		end
		if not debuff then
			debuff = self:GetUnitDebuffInfo("target", i)
		end
		if not debuff then
			break
		end

		local iconMatches = self.buffTextures.flameShock and debuff.icon == self.buffTextures.flameShock
		local nameMatches = debuff.name and debuff.name == self.spells.flameShock
		if iconMatches or nameMatches then
			found = debuff
			break
		end
	end

	if not found then
		if key then
			self.targetDebuffs[key] = nil
		end
		return nil
	end

	local existing = self.targetDebuffs[key]
	if self.pendingShock and self.pendingShock.targetKey == key then
		if not existing then
			existing = {
				name = self.spells.flameShock,
				expiresAt = self.pendingShock.startedAt + 15,
				appliedAt = self.pendingShock.startedAt,
				ownedByPlayer = true,
			}
			self.targetDebuffs[key] = existing
		end
		self.pendingShock = nil
	end

	if not existing or not existing.ownedByPlayer then
		self.targetDebuffs[key] = nil
		return nil
	end

	if key then
		local expiresAt
		if existing and existing.expiresAt > GetTime() then
			expiresAt = existing.expiresAt
		else
			return nil
		end

		self.targetDebuffs[key] = {
			name = self.spells.flameShock,
			expiresAt = expiresAt,
			appliedAt = expiresAt - 15,
			ownedByPlayer = true,
			spellID = found.spellID,
		}

		return self.targetDebuffs[key], expiresAt - GetTime()
	end

	return nil
end

function SRH:TargetHasFlameShockAura()
	local key = self:GetTargetKey()
	if not key then
		return false
	end

	for i = 1, 64 do
		local debuff = nil
		if SpellInfo then
			debuff = self:GetGuidDebuffInfo(key, i)
		end
		if not debuff then
			debuff = self:GetUnitDebuffInfo("target", i)
		end
		if not debuff then
			break
		end

		local iconMatches = self.buffTextures.flameShock and debuff.icon == self.buffTextures.flameShock
		local nameMatches = debuff.name and debuff.name == self.spells.flameShock
		if iconMatches or nameMatches then
			return true
		end
	end

	return false
end

function SRH:OnSpellcastStart(spellName)
	spellName = self:NormalizeSpellName(spellName)
	if spellName ~= self.spells.flameShock then
		self.pendingShock = nil
		return
	end

	local key = self:GetTargetKey()
	if not key then
		self.pendingShock = nil
		return
	end

	self.pendingShock = {
		targetKey = key,
		spell = spellName,
		startedAt = GetTime(),
	}
end

function SRH:OnSpellcastStop()
	if not self.pendingShock then
		return
	end

	local pending = self.pendingShock
	self.pendingShock = nil

	self.targetDebuffs[pending.targetKey] = {
		name = self.spells.flameShock,
		expiresAt = GetTime() + 15,
		appliedAt = GetTime(),
		ownedByPlayer = true,
	}
	self.skipMoltenBlastUntilExpire[pending.targetKey] = nil
end

function SRH:HandleUnitCastEvent(casterGuid, targetGuid, castEvent, spellID, castDuration)
	if not SpellInfo then
		return
	end
	if castEvent ~= "CAST" then
		return
	end
	if not casterGuid or not targetGuid or not spellID then
		return
	end
	if not self.playerGuid then
		local _, playerGuid = UnitExists("player")
		self.playerGuid = playerGuid
	end
	if casterGuid ~= self.playerGuid then
		return
	end

	local spellName = SpellInfo(spellID)
	spellName = self:NormalizeSpellName(spellName)
	if spellName ~= self.spells.flameShock then
		if spellName == self.spells.moltenBlast then
			self.pendingMoltenBlast = {
				targetGuid = targetGuid,
				castAt = GetTime(),
				expiresAt = GetTime() + 4,
			}
		end
		return
	end

	self.pendingShock = nil
	self.targetDebuffs[targetGuid] = {
		name = self.spells.flameShock,
		expiresAt = GetTime() + 15,
		appliedAt = GetTime(),
		ownedByPlayer = true,
		spellID = spellID,
	}
	self.skipMoltenBlastUntilExpire[targetGuid] = nil
end

function SRH:HandleCombatLog(message)
	if not message then
		return
	end

	local lowerMessage = string.lower(message)
	local flameShockLower = string.lower(self.spells.flameShock)
	local moltenBlastLower = string.lower(self.spells.moltenBlast)

	if string.find(lowerMessage, flameShockLower, 1, true) then
		if self.pendingShock and (string.find(lowerMessage, "resist", 1, true) or string.find(lowerMessage, "immune", 1, true) or string.find(lowerMessage, "miss", 1, true)) then
			if string.find(lowerMessage, "immune", 1, true) and self.pendingShock.targetKey then
				self:MarkTargetFireImmune(self.pendingShock.targetKey)
			end
			self.pendingShock = nil
		elseif self.pendingShock and self.pendingShock.targetKey and not string.find(lowerMessage, "resist", 1, true) and not string.find(lowerMessage, "immune", 1, true) and not string.find(lowerMessage, "miss", 1, true) then
			self.targetDebuffs[self.pendingShock.targetKey] = {
				name = self.spells.flameShock,
				expiresAt = GetTime() + 15,
				appliedAt = GetTime(),
				ownedByPlayer = true,
			}
			self.skipMoltenBlastUntilExpire[self.pendingShock.targetKey] = nil
			self.pendingShock = nil
		end
	end

	if string.find(lowerMessage, moltenBlastLower, 1, true) and self.pendingMoltenBlast then
		if string.find(lowerMessage, "immune", 1, true) then
			self:MarkTargetFireImmune(self.pendingMoltenBlast.targetGuid)
		elseif string.find(lowerMessage, "resist", 1, true) or string.find(lowerMessage, "miss", 1, true) then
			if self.pendingMoltenBlast.targetGuid then
				self.skipMoltenBlastUntilExpire[self.pendingMoltenBlast.targetGuid] = true
			end
		elseif not string.find(lowerMessage, "resist", 1, true) and not string.find(lowerMessage, "miss", 1, true) then
			self:RefreshFlameShockFromMoltenBlast(self.pendingMoltenBlast.targetGuid)
		end
		self.pendingMoltenBlast = nil
	end
end

function SRH:CleanupDebuffCache()
	local now = GetTime()

	if self.pendingShock and (now - self.pendingShock.startedAt) > 3 then
		self.pendingShock = nil
	end

	for key, record in pairs(self.targetDebuffs) do
		if record.appliedAt and not record.expiresAt then
			record.expiresAt = record.appliedAt + 15
		end
		if record.expiresAt and not record.appliedAt then
			record.appliedAt = record.expiresAt - 15
		end
		if record.expiresAt <= now then
			self.targetDebuffs[key] = nil
			self.skipMoltenBlastUntilExpire[key] = nil
		end
	end

	if self.pendingMoltenBlast and self.pendingMoltenBlast.expiresAt <= now then
		if self.pendingMoltenBlast.targetGuid and not self.fireImmuneTargets[self.pendingMoltenBlast.targetGuid] and not self.skipMoltenBlastUntilExpire[self.pendingMoltenBlast.targetGuid] then
			self:RefreshFlameShockFromMoltenBlast(self.pendingMoltenBlast.targetGuid)
		end
		self.pendingMoltenBlast = nil
	end
end

function SRH:GetNextRotationSpell()
	local record, remaining = self:GetTargetFlameShockState()
	local hasClearcasting, clearcastingStacks = self:GetPlayerBuffState(self.buffNames.clearcasting, self.buffTextures.clearcasting)
	local selectedShield = self.db.shieldSpell or "Water Shield"
	local fireImmune = self:IsCurrentTargetFireImmune()
	local targetKey = self:GetTargetKey()
	local skipMoltenBlast = targetKey and self.skipMoltenBlastUntilExpire[targetKey]
	local hasShield = false
	local chainLightningCd = self:GetSpellCooldownRemaining(self.spells.chainLightning) or 999
	local hasAnyFlameShockAura = self:TargetHasFlameShockAura()

	if selectedShield == "Water Shield" then
		hasShield = self:HasPlayerBuffByTexture(self.buffTextures.waterShield)
	elseif selectedShield == "Lightning Shield" then
		hasShield = self:HasPlayerBuffByTexture(self.buffTextures.lightningShield)
	elseif selectedShield == "Earth Shield" then
		hasShield = self:HasPlayerBuffByTexture(self.buffTextures.earthShield)
	end

	if self.db.showFlameShock and not fireImmune and not record and not hasAnyFlameShockAura then
		return self.spells.flameShock, "Apply Flame Shock"
	end

	if self.db.showMoltenBlast and not fireImmune and not skipMoltenBlast and record and remaining then
		local startRemaining = self.db.moltenBlastStartRemaining or 6
		local endRemaining = self.db.moltenBlastEndRemaining or 2
		if remaining <= startRemaining and remaining >= endRemaining then
			return self.spells.moltenBlast, string.format("Molten Blast refresh (%ds)", math.ceil(remaining))
		end
	end

	if self.db.onlyChainLightningOnClearcasting then
		if hasClearcasting and (clearcastingStacks >= 2 or clearcastingStacks == 0) and chainLightningCd <= 0 then
			return self.spells.chainLightning, "Chain Lightning"
		end
	elseif chainLightningCd <= 0 then
		return self.spells.chainLightning, "Chain Lightning"
	end

	if self.db.maintainShield and not hasShield then
		return selectedShield, "Refresh " .. selectedShield
	end

	return self.spells.lightningBolt, "Lightning Bolt"
end

function SRH:UpdateCooldownReminder(frame, spellName, enabled)
	if not enabled then
		frame:Hide()
		return
	end

	local spell = self.spellBook[spellName]
	if not spell then
		frame:Hide()
		return
	end

	local remaining = self:GetSpellCooldownRemaining(spellName)
	if remaining == nil or remaining > 0 then
		frame:Hide()
		return
	end

	frame.icon:SetTexture(spell.texture)
	frame.spellName = spellName
	frame.spellBookIndex = spell.index
	frame.tooltipText = nil
	CooldownFrame_SetTimer(frame.cooldown, 0, 0, 0)
	frame:Show()
end

function SRH:RefreshVisuals()
	if not self.frames then
		return
	end

	if not self:IsRotationVisible() then
		self.frames.main:Hide()
		self.frames.em:Hide()
		self.frames.bf:Hide()
		return
	end

	local spellName, label = self:GetNextRotationSpell()
	local spell = self.spellBook[spellName]
	if spell then
		self.frames.main.icon:SetTexture(spell.texture)
		self.frames.main.label:SetText(label)
		self.frames.main.spellName = spellName
		self.frames.main.spellBookIndex = spell.index
		self.frames.main.tooltipText = nil
		local start, duration, enabled = GetSpellCooldown(spell.index, BOOKTYPE_SPELL)
		CooldownFrame_SetTimer(self.frames.main.cooldown, start or 0, duration or 0, enabled or 0)
		self.frames.main:Show()
	else
		self.frames.main:Hide()
	end

	self:UpdateCooldownReminder(self.frames.em, self.spells.elementalMastery, self.db.showElementalMastery)
	self:UpdateCooldownReminder(self.frames.bf, self.spells.bloodFury, self.db.showBloodFury)
end

function SRH:ShowTestIcons()
	if not self.frames then
		return
	end

	local lb = self.spellBook[self.spells.lightningBolt]
	local em = self.spellBook[self.spells.elementalMastery]
	local bf = self.spellBook[self.spells.bloodFury]

	if lb then
		self.frames.main.icon:SetTexture(lb.texture)
		self.frames.main.label:SetText("Test: Lightning Bolt")
		self.frames.main.spellName = self.spells.lightningBolt
		self.frames.main.spellBookIndex = lb.index
		self.frames.main:Show()
	end

	if em then
		self.frames.em.icon:SetTexture(em.texture)
		self.frames.em.spellName = self.spells.elementalMastery
		self.frames.em.spellBookIndex = em.index
		self.frames.em:Show()
	end

	if bf then
		self.frames.bf.icon:SetTexture(bf.texture)
		self.frames.bf.spellName = self.spells.bloodFury
		self.frames.bf.spellBookIndex = bf.index
		self.frames.bf:Show()
	end
end
