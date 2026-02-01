-- Main entry point for the Detachat addon.
local ADDON_NAME = ...
local E, _, V, P, G = unpack(ElvUI)
local GetKeyboardFocus = _G.GetCurrentKeyBoardFocus

-- Module setup: Detachat hooks into ElvUI's chat system and re-anchors edit boxes.
local D = E:NewModule('Detachat', 'AceHook-3.0')
local CH = E:GetModule('Chat')
local LO = E:GetModule('Layout')
-- Pull the localized strings table; fall back to a blank table for safety.
local L = (E.Libs.ACL and E.Libs.ACL:GetLocale(ADDON_NAME, true)) or {}

-- These names are also used by the mover system, so keep them stable.
local MOVER_NAME = 'DetachatInputMover'
local HOLDER_NAME = 'ElvUI_DetachatInputHolder'
local COUNTER_WIDTH = 40
local LABEL_PADDING = 6
local INFINITY_SYMBOL = '∞'

-- Default profile settings for the plugin.
P.detachat = {
	enabled = true,
	matchChatPanelWidth = true,
	matchChatPanel = 'LEFT',
	width = 360,
	height = 22,
	padding = 0,
	inputPadding = 0,
	labelPadding = 6,
	counterPadding = 6,
	strata = 'DIALOG',
	level = 5,
	showCounter = true,
	alwaysShowCounter = false,
	alwaysShowInput = false,
	hideWhenUnfocused = false,
	preventTabFocus = false,
}

-- Public lookup table for options.
D.StrataValues = {
	BACKGROUND = 'BACKGROUND',
	LOW = 'LOW',
	MEDIUM = 'MEDIUM',
	HIGH = 'HIGH',
	DIALOG = 'DIALOG',
	FULLSCREEN = 'FULLSCREEN',
	FULLSCREEN_DIALOG = 'FULLSCREEN_DIALOG',
	TOOLTIP = 'TOOLTIP',
}

-- Ensure the Detachat profile table exists even if the addon loads late.
function D:EnsureDB()
	if not E.db then return false end

	if not E.db.detachat then
		-- Copy defaults so we never mutate the template table directly.
		E.db.detachat = E:CopyTable({}, P.detachat)
	end

	self.db = E.db.detachat
	if self.db.inputPadding == nil and self.db.padding ~= nil then
		self.db.inputPadding = self.db.padding
	end
	return true
end

-- Helper: choose which panel we should match when syncing width.
function D:GetAnchorPanel()
	-- Right panel support is optional; most players only use the left panel.
	if self.db.matchChatPanel == 'RIGHT' then
		return _G.RightChatDataPanel or _G.RightChatPanel
	end

	return _G.LeftChatDataPanel or _G.LeftChatPanel
end

-- Helper: resolve the width the holder should use.
function D:GetDesiredWidth()
	-- Manual width overrides are allowed when the sync toggle is off.
	if not self.db.matchChatPanelWidth then
		return self.db.width
	end

	-- We prefer the data panel width because it's the chat input's native anchor.
	local panel = self:GetAnchorPanel()
	local width = panel and panel.GetWidth and panel:GetWidth()
	if width and width > 0 then
		return width
	end

	-- Fall back to the stored width if the panel isn't ready yet.
	return self.db.width
end

-- Helper: resolve the text padding for label frames.
function D:GetLabelPadding()
	local padding = self.db and self.db.labelPadding
	if padding == nil then
		padding = LABEL_PADDING
	end

	return padding
end

-- Helper: resolve the text padding for the counter frame.
function D:GetCounterPadding()
	local padding = self.db and self.db.counterPadding
	if padding == nil then
		padding = LABEL_PADDING
	end

	return padding
end

-- Helper: resolve the edit box padding inside the input frame.
function D:GetInputPadding()
	local padding = self.db and self.db.inputPadding
	if padding == nil then
		padding = self.db and self.db.padding
	end

	return padding or 0
end

-- Keep the holder's size and layer settings in sync with the database.
function D:UpdateHolderLayout()
	if not self.Holder then return end

	-- The holder drives the mover size and the edit box anchors.
	self.Holder:Size(self:GetDesiredWidth(), self.db.height)
	self.Holder:SetFrameStrata(self.db.strata)
	-- A small bump keeps the edit box above the holder when they share strata.
	self.Holder:SetFrameLevel(self.db.level)

	if self.TypeFrame then
		self.TypeFrame:SetFrameStrata(self.Holder:GetFrameStrata())
		self.TypeFrame:SetFrameLevel(self.Holder:GetFrameLevel())
	end

	if self.NameFrame then
		self.NameFrame:SetFrameStrata(self.Holder:GetFrameStrata())
		self.NameFrame:SetFrameLevel(self.Holder:GetFrameLevel())
	end

	if self.RealmFrame then
		self.RealmFrame:SetFrameStrata(self.Holder:GetFrameStrata())
		self.RealmFrame:SetFrameLevel(self.Holder:GetFrameLevel())
	end

	if self.InputFrame then
		self.InputFrame:SetFrameStrata(self.Holder:GetFrameStrata())
		self.InputFrame:SetFrameLevel(self.Holder:GetFrameLevel())
	end

	if self.CounterFrame then
		self.CounterFrame:SetFrameStrata(self.Holder:GetFrameStrata())
		self.CounterFrame:SetFrameLevel(self.Holder:GetFrameLevel())
	end
end

-- Place the holder on top of the default chat input area when possible.
function D:RefreshDefaultPosition()
	if not self.Holder then return end
	if E:HasMoverBeenMoved(MOVER_NAME) then return end

	-- If no saved mover position exists, snap to the current chat panel.
	local anchor = self:GetAnchorPanel()
	if not anchor then return end

	self.Holder:ClearAllPoints()
	self.Holder:Point('TOPLEFT', anchor, 'TOPLEFT', 0, 0)

	-- Update the mover origin so reset returns to the correct spot.
	local mover = E.CreatedMovers and E.CreatedMovers[MOVER_NAME]
	if mover then
		mover.originPoint = { self.Holder:GetPoint() }
		E:SetMoverPoints(MOVER_NAME, self.Holder)
	end
end

-- Create the invisible holder frame that the mover attaches to.
function D:CreateHolder()
	if self.Holder then return end

	-- Holder is a pure anchor; the edit boxes remain the real input widgets.
	local holder = CreateFrame('Frame', HOLDER_NAME, E.UIParent)
	-- Use TOPLEFT so mover math stays consistent across sessions.
	holder:Point('TOPLEFT', E.UIParent, 'TOPLEFT', 0, 0)
	holder:Size(self.db.width, self.db.height)
	self.Holder = holder

	-- Establish a sane default position before the mover captures origin data.
	self:RefreshDefaultPosition()

	-- Create a mover so users can place the input anywhere.
	E:CreateMover(holder, MOVER_NAME, L["Chat Input"] or 'Chat Input', nil, nil, nil, nil, nil, 'chat,detachat')
end

-- Create the header frames that sit to the left of the input.
function D:CreateHeaderFrames()
	if self.TypeFrame then return end

	local fallbackFont = (E.media and E.media.normFont) or _G.STANDARD_TEXT_FONT
	local fallbackSize = (E.db and E.db.general and E.db.general.fontSize) or 12

	local function CreateLabelFrame(suffix)
		local frame = CreateFrame('Frame', HOLDER_NAME..suffix, self.Holder or E.UIParent)
		frame:SetTemplate(nil, true)
		frame.Text = frame:CreateFontString(nil, 'ARTWORK')
		frame.Text:SetJustifyH('CENTER')
		if fallbackFont then
			frame.Text:SetFont(fallbackFont, fallbackSize)
		end
		return frame
	end

	self.TypeFrame = CreateLabelFrame('Type')
	self.NameFrame = CreateLabelFrame('Name')
	self.RealmFrame = CreateLabelFrame('Realm')

	-- InputFrame is an anchor for the edit box; the edit box provides its own border.
	self.InputFrame = CreateFrame('Frame', HOLDER_NAME..'Input', self.Holder or E.UIParent)
end

-- Create a separate frame for the character counter.
function D:CreateCounterFrame()
	if self.CounterFrame or not self.Holder then return end

	local fallbackFont = (E.media and E.media.normFont) or _G.STANDARD_TEXT_FONT
	local fallbackSize = (E.db and E.db.general and E.db.general.fontSize) or 12

	local frame = CreateFrame('Frame', HOLDER_NAME..'Counter', self.Holder or E.UIParent)
	frame:Point('LEFT', self.Holder, 'RIGHT', (E.Spacing or 1) + (E.Border or 1), 0)
	frame:Size(COUNTER_WIDTH, self.db.height)
	frame:SetFrameStrata(self.db.strata)
	frame:SetFrameLevel(self.db.level)
	frame:SetTemplate(nil, true)
	frame.Text = frame:CreateFontString(nil, 'ARTWORK')
	frame.Text:SetJustifyH('CENTER')
	if fallbackFont then
		frame.Text:SetFont(fallbackFont, fallbackSize)
	end
	self.CounterFrame = frame
end

-- Apply text padding inside the header and counter frames.
function D:ApplyHeaderPadding()
	local labelPadding = self:GetLabelPadding()
	local frames = { self.TypeFrame, self.NameFrame, self.RealmFrame }

	for _, frame in ipairs(frames) do
		if frame and frame.Text then
			frame.Text:ClearAllPoints()
			frame.Text:SetPoint('LEFT', frame, 'LEFT', labelPadding, 0)
			frame.Text:SetPoint('RIGHT', frame, 'RIGHT', -labelPadding, 0)
		end
	end

	local counterPadding = self:GetCounterPadding()
	if self.CounterFrame and self.CounterFrame.Text then
		self.CounterFrame.Text:ClearAllPoints()
		self.CounterFrame.Text:SetPoint('LEFT', self.CounterFrame, 'LEFT', counterPadding, 0)
		self.CounterFrame.Text:SetPoint('RIGHT', self.CounterFrame, 'RIGHT', -counterPadding, 0)
	end
end

-- Match the counter font and color to ElvUI's character count font.
function D:SyncCounterFont(editbox)
	if not (self.CounterFrame and self.CounterFrame.Text and editbox and editbox.characterCount) then return end

	local font, size, flags = editbox.characterCount:GetFont()
	if font then
		self.CounterFrame.Text:SetFont(font, size, flags)
	end

	local r, g, b, a = editbox.characterCount:GetTextColor()
	self.CounterFrame.Text:SetTextColor(r, g, b, a)
end

-- Build the display label for a given chat type.
function D:GetChatTypeLabel(chatType, chanTarget)
	if chatType == 'CHANNEL' and chanTarget then
		local index, name = GetChannelName(chanTarget)
		if name and name ~= '' then
			if index and index > 0 then
				return format('%d. %s', index, name)
			end
			return name
		end
	end

	local labels = {
		SAY = _G.SAY or 'Say',
		YELL = _G.YELL or 'Yell',
		EMOTE = _G.EMOTE or 'Emote',
		GUILD = _G.GUILD or 'Guild',
		OFFICER = _G.OFFICER or 'Officer',
		PARTY = _G.PARTY or 'Party',
		RAID = _G.RAID or 'Raid',
		RAID_WARNING = _G.RAID_WARNING or 'Raid',
		INSTANCE_CHAT = _G.INSTANCE or 'Instance',
		WHISPER = _G.WHISPER or 'Whisper',
		BN_WHISPER = _G.WHISPER or 'Whisper',
		CHANNEL = _G.CHANNEL or 'Channel',
	}

	return labels[chatType] or chatType
end

-- Resolve the whisper target into name + realm parts.
function D:GetWhisperTarget(editbox)
	local target = editbox:GetAttribute('tellTarget') or editbox:GetAttribute('bnetTarget') or editbox:GetAttribute('chatTarget')
	if not target or target == '' then return nil end

	local name, realm = strsplit('-', target)
	if name and name ~= '' then
		return name, realm
	end
end

-- Apply the chat-type text color while matching the edit box backdrop and border styling.
function D:ApplyHeaderColors(info, editbox)
	local r, g, b = 1, 1, 1
	if info then
		r, g, b = info.r or 1, info.g or 1, info.b or 1
	end

	local backR, backG, backB, backA
	local borderR, borderG, borderB, borderA
	if editbox and editbox.GetBackdropColor then
		backR, backG, backB, backA = editbox:GetBackdropColor()
	end
	if editbox and editbox.GetBackdropBorderColor then
		borderR, borderG, borderB, borderA = editbox:GetBackdropBorderColor()
	end

	if not borderR and E.media and E.media.bordercolor then
		borderR, borderG, borderB, borderA = E.media.bordercolor.r, E.media.bordercolor.g, E.media.bordercolor.b, E.media.bordercolor.a or 1
	end

	local frames = { self.TypeFrame, self.NameFrame, self.RealmFrame }
	for _, frame in ipairs(frames) do
		if frame then
			if editbox and editbox.template and frame.SetTemplate then
				frame:SetTemplate(editbox.template, true)
			end
			if frame.Text then
				frame.Text:SetTextColor(r, g, b)
			end
			if borderR and frame.SetBackdropBorderColor then
				frame:SetBackdropBorderColor(borderR, borderG, borderB, borderA)
			end
			if backR and frame.SetBackdropColor then
				frame:SetBackdropColor(backR, backG, backB, backA)
			end
		end
	end
end

-- Update header frames and layout based on the active chat type.
function D:UpdateHeaderFrames(editbox)
	if not editbox or not self.Holder then return end
	self:CreateHeaderFrames()

	local chatType = editbox:GetAttribute('chatType') or 'SAY'
	local chanTarget = editbox:GetAttribute('channelTarget')
	local info = _G.ChatTypeInfo and _G.ChatTypeInfo[chatType]

	if chatType == 'CHANNEL' and chanTarget then
		local index = GetChannelName(chanTarget)
		if index and index > 0 then
			info = _G.ChatTypeInfo[chatType..index] or info
		end
	end

	local typeLabel = self:GetChatTypeLabel(chatType, chanTarget)
	local name, realm
	if chatType == 'WHISPER' or chatType == 'BN_WHISPER' or chatType == 'REPLY' or chatType == 'BN_REPLY' then
		name, realm = self:GetWhisperTarget(editbox)
	end

	-- Use the editbox font for label frames.
	local font, size, flags = editbox:GetFont()
	if font then
		self.TypeFrame.Text:SetFont(font, size, flags)
		self.NameFrame.Text:SetFont(font, size, flags)
		self.RealmFrame.Text:SetFont(font, size, flags)
	end

	self.TypeFrame.Text:SetText(typeLabel or '')
	self.TypeFrame:SetShown(typeLabel and typeLabel ~= '')

	self.NameFrame.Text:SetText(name or '')
	self.NameFrame:SetShown(name and name ~= '')

	self.RealmFrame.Text:SetText(realm or '')
	self.RealmFrame:SetShown(realm and realm ~= '')

	self:ApplyHeaderColors(info, editbox)
	self:SyncCounterFont(editbox)
	if self.db.showCounter then
		self:SyncCounterStyle(editbox)
	end
	self:ApplyHeaderPadding()

	-- Calculate widths based on text content.
	local labelPadding = self:GetLabelPadding()
	local counterPadding = self:GetCounterPadding()

	local function FrameWidth(frame)
		if not frame:IsShown() then return 0 end
		return frame.Text:GetStringWidth() + (labelPadding * 2)
	end

	local typeWidth = FrameWidth(self.TypeFrame)
	local nameWidth = FrameWidth(self.NameFrame)
	local realmWidth = FrameWidth(self.RealmFrame)
	local inputWidth = self:GetDesiredWidth()
	local counterTextWidth = (self.CounterFrame and self.CounterFrame.Text and self.CounterFrame.Text:GetStringWidth()) or 0
	local counterWidth = 0
	if self.db.showCounter then
		counterWidth = math.max(COUNTER_WIDTH, counterTextWidth + (counterPadding * 2))
	end

	-- Layout left-to-right.
	local spacing = (E.Spacing or 1) + (E.Border or 1)
	local current = self.Holder
	local total = 0

	local function Place(frame, width)
		if not frame then return end
		frame:ClearAllPoints()
		if current == self.Holder then
			frame:Point('TOPLEFT', self.Holder, 'TOPLEFT', 0, 0)
		else
			frame:Point('LEFT', current, 'RIGHT', spacing, 0)
			total = total + spacing
		end
		frame:Size(width, self.db.height)
		current = frame
		total = total + width
	end

	if typeWidth > 0 then Place(self.TypeFrame, typeWidth) end
	if nameWidth > 0 then Place(self.NameFrame, nameWidth) end
	if realmWidth > 0 then Place(self.RealmFrame, realmWidth) end

	-- Input anchor.
	self.InputFrame:ClearAllPoints()
	if current == self.Holder then
		self.InputFrame:Point('TOPLEFT', self.Holder, 'TOPLEFT', 0, 0)
	else
		self.InputFrame:Point('LEFT', current, 'RIGHT', spacing, 0)
		total = total + spacing
	end
	self.InputFrame:Size(inputWidth, self.db.height)
	current = self.InputFrame
	total = total + inputWidth

	-- Counter anchor.
	if self.db.showCounter and self.CounterFrame then
		self.CounterFrame:ClearAllPoints()
		self.CounterFrame:Point('LEFT', current, 'RIGHT', spacing, 0)
		self.CounterFrame:Size(counterWidth, self.db.height)
		self.CounterFrame:SetFrameStrata(self.Holder:GetFrameStrata())
		self.CounterFrame:SetFrameLevel(self.Holder:GetFrameLevel())
		total = total + spacing + counterWidth
	end

	self.Holder:Size(total, self.db.height)
end

-- Remove the extra right inset ElvUI adds for the in-box counter.
function D:UpdateTextInsets(editbox)
	if not editbox or not editbox.GetTextInsets then return end

	local _, insetRight, insetTop, insetBottom = editbox:GetTextInsets()

	-- Blizzard pads the left side to fit the header text; we want custom input padding instead.
	local padding = self:GetInputPadding()
	local leftInset = math.max(0, padding)
	local rightInset = math.max(0, (insetRight or 0) - 30) + math.max(0, padding)
	editbox:SetTextInsets(leftInset, rightInset, insetTop or 0, insetBottom or 0)
end

-- Enforce inset adjustments even if other code re-applies padding.
function D:InstallInsetHook(editbox)
	if not editbox or editbox.detachatInsetHooked or not editbox.SetTextInsets then return end

	local module = self
	hooksecurefunc(editbox, 'SetTextInsets', function(box, left, right, top, bottom)
		if box.detachatSkipInsetHook then return end
		if not module.db or not module.db.enabled then return end

		box.detachatSkipInsetHook = true
		local padding = module:GetInputPadding()
		local fixedRight = math.max(0, (right or 0) - 30) + math.max(0, padding)
		box:SetTextInsets(math.max(0, padding), fixedRight, top or 0, bottom or 0)
		box.detachatSkipInsetHook = false
	end)

	editbox.detachatInsetHooked = true
end

-- Anchor the counter either inside the edit box or inside the detached frame.
function D:ApplyCounterMode(editbox)
	if not (editbox and editbox.characterCount) then return end

	if self.db.showCounter then
		self:CreateCounterFrame()
		editbox.characterCount:Hide()
		self:SyncCounterFont(editbox)
		self:SyncCounterStyle(editbox)
	else
		-- Restore the original ElvUI anchor when the counter frame is hidden.
		editbox.characterCount:Show()
		editbox.characterCount:ClearAllPoints()
		editbox.characterCount:Point('TOPRIGHT', editbox, 'TOPRIGHT', -5, 0)
		editbox.characterCount:Point('BOTTOMRIGHT', editbox, 'BOTTOMRIGHT', -5, 0)
	end
end

-- Copy the edit box backdrop to the counter frame so they match.
function D:SyncCounterStyle(editbox)
	if not (self.CounterFrame and editbox) then return end

	if editbox.template then
		self.CounterFrame:SetTemplate(editbox.template, true)
	end

	if editbox.GetBackdropBorderColor and self.CounterFrame.SetBackdropBorderColor then
		local r, g, b, a = editbox:GetBackdropBorderColor()
		self.CounterFrame:SetBackdropBorderColor(r, g, b, a)
	end

	if editbox.GetBackdropColor and self.CounterFrame.SetBackdropColor then
		local r, g, b, a = editbox:GetBackdropColor()
		self.CounterFrame:SetBackdropColor(r, g, b, a)
	end
end

-- Use ElvUI's normal border color for the idle counter state.
function D:SetCounterDefaultBorder()
	if not self.CounterFrame then return end

	local color = E.media and E.media.bordercolor
	if color then
		self.CounterFrame:SetBackdropBorderColor(color.r, color.g, color.b, color.a or 1)
	end
end

-- Determine the maximum characters for the chat input.
function D:GetMaxCharacters(editbox)
	if editbox and editbox.GetMaxLetters then
		local max = editbox:GetMaxLetters()
		if max and max > 0 then
			return max
		end
	end

	-- Chat edit boxes default to 255 characters.
	return 255
end

-- Always show the full character limit when the box is empty.
function D:UpdateCharacterCountDisplay(editbox)
	if not editbox then return end

	local display = editbox.characterCount
	if self.db.showCounter and self.CounterFrame and self.CounterFrame.Text then
		display = self.CounterFrame.Text
	end

	if not display then return end

	if editbox.HasFocus and not editbox:HasFocus() then
		if editbox.characterCount then
			editbox.detachatLastCount = editbox.characterCount:GetText()
		end
		display:SetText(INFINITY_SYMBOL)
		return
	end

	local text = editbox:GetText() or ''
	if text == '' then
		display:SetText(self:GetMaxCharacters(editbox))
	elseif display:GetText() == INFINITY_SYMBOL then
		if editbox.detachatLastCount and editbox.detachatLastCount ~= '' then
			display:SetText(editbox.detachatLastCount)
		end
	elseif editbox.characterCount and editbox.characterCount:GetText() ~= '' then
		display:SetText(editbox.characterCount:GetText())
	end
end

-- Use ElvUI's normal border color for the edit box when not focused.
function D:SetEditBoxDefaultBorder(editbox)
	if not editbox then return end

	local color = E.media and E.media.bordercolor
	if color and editbox.SetBackdropBorderColor then
		editbox:SetBackdropBorderColor(color.r, color.g, color.b, color.a or 1)
	end
end

-- Ensure the edit box border matches focus state expectations.
function D:SyncEditBoxBorder(editbox)
	if not editbox or not editbox.HasFocus then return end

	if editbox:HasFocus() then
		if CH and CH.ChatEdit_UpdateHeader then
			CH:ChatEdit_UpdateHeader(editbox)
		end
	else
		self:SetEditBoxDefaultBorder(editbox)
	end
end

-- Ensure the border stays in the expected state after ElvUI updates it.
function D:OnChatEditUpdateHeader(_, editbox)
	if not editbox then return end

	self:UpdateHeaderFrames(editbox)
	self:UpdateTextInsets(editbox)
	self:InstallInsetHook(editbox)
	self:UpdateCharacterCountDisplay(editbox)
	if editbox.header then
		editbox.header:Hide()
	end
	if editbox.HasFocus and not editbox:HasFocus() then
		self:SetEditBoxDefaultBorder(editbox)
	end
end

-- Pick the edit box that currently owns the chat input.
function D:GetActiveEditBox()
	for _, frameName in ipairs(_G.CHAT_FRAMES) do
		local chat = _G[frameName]
		local editbox = chat and chat.editBox
		if editbox and editbox:IsShown() then
			return editbox
		end
	end
end

-- Show or hide the counter frame based on edit box visibility.
function D:UpdateCounterVisibility()
	if not self.CounterFrame then return end

	if not self.db.showCounter then
		self.CounterFrame:Hide()
		return
	end

	local editbox = self:GetActiveEditBox()

	if editbox then
		self.CounterFrame:Show()
		if editbox:HasFocus() then
			self:SyncCounterStyle(editbox)
		else
			self:SetCounterDefaultBorder()
		end
		return
	end

	if self.db.alwaysShowCounter then
		self.CounterFrame:Show()
		self:SetCounterDefaultBorder()
	else
		self.CounterFrame:Hide()
	end
end

-- Apply visibility rules to a single edit box.
function D:UpdateEditBoxVisibility(editbox)
	if not editbox then return end

	if self.db.alwaysShowInput then
		editbox:Show()
		self:SyncEditBoxBorder(editbox)
		return
	end

	local focused = editbox:HasFocus()
	if self.db.hideWhenUnfocused then
		if focused then
			editbox:Show()
			self:SyncEditBoxBorder(editbox)
		else
			editbox:Hide()
		end
		return
	end

	local style = editbox.chatStyle or GetCVar('chatStyle')
	if style == 'im' then
		if focused then
			editbox:Show()
			self:SyncEditBoxBorder(editbox)
		else
			if CH and CH.ChatEdit_DeactivateChat then
				CH:ChatEdit_DeactivateChat(editbox)
			else
				editbox:Hide()
			end
		end
	else
		-- Classic style keeps inputs visible by default.
		editbox:Show()
		self:SyncEditBoxBorder(editbox)
	end
end

-- Control auto-focus behavior so showing the edit box doesn't steal focus.
function D:UpdateEditBoxAutoFocus(editbox)
	if not editbox or not editbox.SetAutoFocus then return end

	if editbox.detachatOriginalAutoFocus == nil then
		local getter = editbox.GetAutoFocus or editbox.IsAutoFocus
		editbox.detachatOriginalAutoFocus = getter and getter(editbox)
	end

	local shouldAutoFocus = editbox.detachatOriginalAutoFocus
	if self.db.preventTabFocus or self.db.alwaysShowInput then
		shouldAutoFocus = false
	end

	editbox:SetAutoFocus(shouldAutoFocus ~= false)
end

-- Check if a frame is one of the chat edit boxes.
function D:IsChatEditBox(frame)
	if not frame then return false end

	for _, frameName in ipairs(_G.CHAT_FRAMES) do
		local chat = _G[frameName]
		if chat and chat.editBox == frame then
			return true
		end
	end

	return false
end

-- Prevent tab clicks from focusing the chat input by restoring prior focus.
function D:FCF_Tab_OnClick(tab, button)
	local previousFocus = GetKeyboardFocus and GetKeyboardFocus() or nil

	self.hooks[CH].FCF_Tab_OnClick(tab, button)

	if not self.db.preventTabFocus then return end

	local newFocus = GetKeyboardFocus and GetKeyboardFocus() or nil
	if newFocus == previousFocus then return end

	if self:IsChatEditBox(newFocus) then
		if previousFocus and previousFocus.SetFocus then
			previousFocus:SetFocus()
		elseif newFocus and newFocus.ClearFocus then
			newFocus:ClearFocus()
		end

		self:UpdateEditBoxVisibility(newFocus)
		self:SyncEditBoxBorder(newFocus)
	end
end

-- Apply the desired visibility behavior to all chat edit boxes.
function D:ApplyInputVisibility()
	for _, frameName in ipairs(_G.CHAT_FRAMES) do
		local chat = _G[frameName]
		local editbox = chat and chat.editBox
		if editbox then
			self:UpdateEditBoxVisibility(editbox)
		end
	end
end

-- Anchor all chat edit boxes to the holder so they move together.
function D:RepositionEditBoxes()
	if not self.db.enabled then return end
	if not self.Holder then return end

	self:CreateHeaderFrames()

	if self.db.showCounter then
		self:CreateCounterFrame()
	elseif self.CounterFrame then
		self.CounterFrame:Hide()
	end

	-- Text padding is handled via text insets; the edit box fills the input frame.

	-- ElvUI creates one edit box per chat frame; we anchor them all.
	for _, frameName in ipairs(_G.CHAT_FRAMES) do
		local chat = _G[frameName]
		local editbox = chat and chat.editBox
		if editbox then
			self:UpdateHeaderFrames(editbox)

			if editbox.header then
				editbox.header:Hide()
			end

			-- Clear default ElvUI anchors and stick to the detached holder.
			editbox:ClearAllPoints()
			editbox:Point('TOPLEFT', self.InputFrame, 0, 0)
			editbox:Point('BOTTOMRIGHT', self.InputFrame, 0, 0)

			-- We do not reparent to avoid taint/secure edit box edge cases.
			-- Match the holder's layer so the input stays visible.
			editbox:SetFrameStrata(self.Holder:GetFrameStrata())
			-- Keep the input slightly above the holder to avoid click issues.
			editbox:SetFrameLevel(self.Holder:GetFrameLevel() + 1)

			self:UpdateTextInsets(editbox)
			self:InstallInsetHook(editbox)

			-- Move the character counter into the detached frame.
			self:ApplyCounterMode(editbox)
			self:SyncEditBoxBorder(editbox)
			self:UpdateEditBoxAutoFocus(editbox)
			self:UpdateCharacterCountDisplay(editbox)

			if not editbox.detachatCounterHooked then
				editbox:HookScript('OnShow', function() self:UpdateCounterVisibility() end)
				editbox:HookScript('OnHide', function(box)
					self:UpdateCounterVisibility()
					if self.db.alwaysShowInput and not box.detachatForceShow then
						box.detachatForceShow = true
						box:Show()
						box.detachatForceShow = false
					end
				end)
				editbox:HookScript('OnEditFocusGained', function(box)
					self:UpdateCounterVisibility()
					self:UpdateEditBoxVisibility(box)
					self:SyncEditBoxBorder(box)
					self:UpdateCharacterCountDisplay(box)
				end)
				editbox:HookScript('OnEditFocusLost', function(box)
					self:UpdateCounterVisibility()
					self:UpdateEditBoxVisibility(box)
					self:SyncEditBoxBorder(box)
					self:UpdateCharacterCountDisplay(box)
				end)
				editbox:HookScript('OnTextChanged', function(box)
					self:UpdateCharacterCountDisplay(box)
				end)
				editbox.detachatCounterHooked = true
			end
		end
	end

	self:UpdateCounterVisibility()
end

-- Return edit boxes to ElvUI's default anchoring when Detachat is disabled.
function D:ReleaseEditBoxes()
	-- Let ElvUI rebuild its default anchors when we step aside.
	if CH and CH.UpdateEditboxAnchors then
		CH:UpdateEditboxAnchors()
	end
end

-- Apply all settings in one place so the options panel stays clean.
function D:ApplySettings()
	-- Cache the profile table so every helper can use self.db.
	if not self:EnsureDB() then return end

	-- Disable flow: hide the holder and restore default anchoring.
	if not self.db.enabled or not E.private.chat.enable then
		if self.Holder then
			self.Holder:Hide()
		end
		if self.CounterFrame then
			self.CounterFrame:Hide()
		end
		self:ReleaseEditBoxes()
		return
	end

	-- Enable flow: ensure holder exists and apply all layout changes.
	self:CreateHolder()
	-- The holder is a silent anchor; no visuals need to be shown.
	self.Holder:Show()
	self:UpdateHolderLayout()
	self:RefreshDefaultPosition()
	self:RepositionEditBoxes()
	self:ApplyInputVisibility()
end

-- Hook ElvUI so our anchors re-apply after its own updates.
function D:InstallHooks()
	if self.HooksInstalled then return end

	-- Update anchors after ElvUI modifies them.
	self:SecureHook(CH, 'UpdateEditboxAnchors', 'RepositionEditBoxes')
	self:SecureHook(CH, 'StyleChat', 'RepositionEditBoxes')
	self:SecureHook(CH, 'ChatEdit_UpdateHeader', 'OnChatEditUpdateHeader')
	self:SecureHook(CH, 'ChatEdit_DeactivateChat', function(_, editbox)
		if self.db.alwaysShowInput and editbox then
			editbox:Show()
		end
	end)
	self:RawHook(CH, 'FCF_Tab_OnClick', 'FCF_Tab_OnClick', true)

	-- Re-apply layout when chat panels are resized or repositioned.
	self:SecureHook(CH, 'PositionChats', 'ApplySettings')
	self:SecureHook(LO, 'RepositionChatDataPanels', 'ApplySettings')

	self.HooksInstalled = true
end

-- Called once by ElvUI during startup.
function D:Initialize()
	if not self:EnsureDB() then return end

	-- Only run if ElvUI chat is available.
	if not E.private.chat.enable then return end

	-- Keep the setup order stable: holder, hooks, then initial layout.
	self:CreateHolder()
	self:InstallHooks()
	self:ApplySettings()
end

-- Disable the default chat editbox position selector when options load.
function D:DisableElvUIEditBoxOptions()
	if not E.Options or not E.Options.args or not E.Options.args.chat then return end

	local general = E.Options.args.chat.args and E.Options.args.chat.args.general
	local option = general and general.args and general.args.editBoxPosition
	if not option then return end

	-- Lock the dropdown so Detachat is the sole source of truth.
	option.disabled = function() return true end
	option.desc = (option.desc and option.desc .. ' ' or '') .. (L["Detachat manages the chat input position."] or 'Detachat manages the chat input position.')
end

E:RegisterModule(D:GetName())
