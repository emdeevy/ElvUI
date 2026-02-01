-- Main entry point for the Detachat addon.
local ADDON_NAME = ...
local E, _, V, P, G = unpack(ElvUI)
local GetFocus = _G.GetFocus or _G.GetCurrentKeyBoardFocus

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
local INFINITY_SYMBOL = '∞'

-- Default profile settings for the plugin.
P.detachat = {
	enabled = true,
	matchChatPanelWidth = true,
	matchChatPanel = 'LEFT',
	width = 360,
	height = 22,
	padding = 0,
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

-- Keep the holder's size and layer settings in sync with the database.
function D:UpdateHolderLayout()
	if not self.Holder then return end

	-- The holder drives the mover size and the edit box anchors.
	self.Holder:Size(self:GetDesiredWidth(), self.db.height)
	self.Holder:SetFrameStrata(self.db.strata)
	-- A small bump keeps the edit box above the holder when they share strata.
	self.Holder:SetFrameLevel(self.db.level)

	if self.CounterFrame then
		local spacing = (E.Spacing or 1) + (E.Border or 1)
		self.CounterFrame:ClearAllPoints()
		self.CounterFrame:Point('LEFT', self.Holder, 'RIGHT', spacing, 0)
		self.CounterFrame:Size(COUNTER_WIDTH, self.db.height)
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

-- Create a separate frame for the character counter.
function D:CreateCounterFrame()
	if self.CounterFrame or not self.Holder then return end

	local frame = CreateFrame('Frame', HOLDER_NAME..'Counter', E.UIParent)
	frame:Point('LEFT', self.Holder, 'RIGHT', (E.Spacing or 1) + (E.Border or 1), 0)
	frame:Size(COUNTER_WIDTH, self.db.height)
	frame:SetFrameStrata(self.db.strata)
	frame:SetFrameLevel(self.db.level)
	frame:SetTemplate(nil, true)
	frame.Text = frame:CreateFontString(nil, 'ARTWORK')
	frame.Text:SetPoint('CENTER')
	frame.Text:SetJustifyH('CENTER')
	self.CounterFrame = frame
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

	self:SyncCounterStyle(editbox)
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
	local previousFocus = GetFocus and GetFocus() or nil

	self.hooks[CH].FCF_Tab_OnClick(tab, button)

	if not self.db.preventTabFocus then return end

	local newFocus = GetFocus and GetFocus() or nil
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

	if self.db.showCounter then
		self:CreateCounterFrame()
	elseif self.CounterFrame then
		self.CounterFrame:Hide()
	end

	-- Padding lets us inset the edit box without changing its template.
	local padding = self.db.padding or 0
	-- Guard against negative padding that would invert the inset.
	if padding < 0 then padding = 0 end

	-- ElvUI creates one edit box per chat frame; we anchor them all.
	for _, frameName in ipairs(_G.CHAT_FRAMES) do
		local chat = _G[frameName]
		local editbox = chat and chat.editBox
		if editbox then
			-- Clear default ElvUI anchors and stick to the detached holder.
			editbox:ClearAllPoints()
			editbox:Point('TOPLEFT', self.Holder, padding, -padding)
			editbox:Point('BOTTOMRIGHT', self.Holder, -padding, padding)

			-- We do not reparent to avoid taint/secure edit box edge cases.
			-- Match the holder's layer so the input stays visible.
			editbox:SetFrameStrata(self.Holder:GetFrameStrata())
			-- Keep the input slightly above the holder to avoid click issues.
			editbox:SetFrameLevel(self.Holder:GetFrameLevel() + 1)

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
