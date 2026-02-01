-- Options table for Detachat. Loaded only when ElvUI_Options is present.
-- Options table for Detachat. Loaded only when ElvUI_Options is present.
local ADDON_NAME = ...
local E, EL, V, P, G = unpack(ElvUI)

local D = E:GetModule('Detachat')
local ACH = E.Libs.ACH
local EP = E.Libs.EP
-- Fetch localized strings at runtime to avoid AceLocale write-proxy issues.
local L = (E.Libs.ACL and E.Libs.ACL:GetLocale(ADDON_NAME, true)) or {}

-- Standard getters/setters keep option definitions concise.
local function Get(info)
	if not D:EnsureDB() then return end
	return E.db.detachat[info[#info]]
end

local function Set(info, value)
	if not D:EnsureDB() then return end
	E.db.detachat[info[#info]] = value
	D:ApplySettings()
end

-- Disabled helper used by most sub-groups when Detachat is off.
local function IsDisabled()
	return not E.db.detachat.enabled
end

function D:AddOptions()
	if not E.Options then return end

	-- Root options group: keep it near other top-level ElvUI groups.
	local options = ACH:Group(L["Detachat"] or 'Detachat', nil, 100, nil, Get, Set)
	E.Options.args.detachat = options

	-- Basic header and short description.
	options.args.header = ACH:Header(L["Detachat"] or 'Detachat', 1)
	options.args.description = ACH:Description(L["DETACHAT_DESC"] or 'Detach the chat input so it can be freely moved with a mover.', 2, 'medium')

	-- Enable toggle uses a dedicated setter to rebuild anchors immediately.
	options.args.enable = ACH:Toggle(L["Enable"] or 'Enable', nil, 3, nil, nil, nil, nil, function(info, value)
		E.db.detachat[info[#info]] = value
		D:ApplySettings()
	end)

	-- Size controls define the holder frame (not the edit box template).
	local size = ACH:Group(L["Size & Position"] or 'Size & Position', nil, 10, nil, nil, nil, IsDisabled)
	options.args.size = size
	size.inline = true

	size.args.matchChatPanelWidth = ACH:Toggle(L["Match Chat Panel Width"] or 'Match Chat Panel Width', L["Match the input width to the selected chat panel."] or 'Match the input width to the selected chat panel.', 1)
	
	size.args.matchChatPanel = ACH:Select(
		L["Chat Panel"] or 'Chat Panel',
		L["Which chat panel to match when syncing width."] or 'Which chat panel to match when syncing width.',
		2,
		{ LEFT = L["Left"] or 'Left', RIGHT = L["Right"] or 'Right' },
		nil,
		nil,
		nil,
		nil,
		function()
			return not E.db.detachat.matchChatPanelWidth
		end
	)

	-- Manual width is only exposed when syncing is disabled.
	size.args.width = ACH:Range(L["Width"] or 'Width', nil, 3, { min = 120, max = 1200, step = 1 }, nil, nil, nil, function()
		return E.db.detachat.matchChatPanelWidth
	end)

	-- Height and padding always apply to the holder.
	size.args.height = ACH:Range(L["Height"] or 'Height', nil, 4, { min = 18, max = 60, step = 1 })
	size.args.padding = ACH:Range(L["Padding"] or 'Padding', L["Inset the input within the holder."] or 'Inset the input within the holder.', 5, { min = 0, max = 20, step = 1 })

	-- Counter controls live with size settings to keep them discoverable.
	size.args.alwaysShowInput = ACH:Toggle(L["Always Show Input"] or 'Always Show Input', L["Keep the chat input visible even when it is not focused."] or 'Keep the chat input visible even when it is not focused.', 6)
	size.args.hideWhenUnfocused = ACH:Toggle(L["Hide When Unfocused"] or 'Hide When Unfocused', L["Hide the chat input when it is not focused (overrides classic behavior)."] or 'Hide the chat input when it is not focused (overrides classic behavior).', 7, nil, nil, nil, nil, nil, function()
		return E.db.detachat.alwaysShowInput
	end)
	size.args.preventTabFocus = ACH:Toggle(L["Prevent Tab Auto Focus"] or 'Prevent Tab Auto Focus', L["Keep the chat input from auto-focusing when switching tabs."] or 'Keep the chat input from auto-focusing when switching tabs.', 8)
	size.args.showCounter = ACH:Toggle(L["Show Counter"] or 'Show Counter', L["Display the character counter frame next to the input."] or 'Display the character counter frame next to the input.', 9)
	size.args.alwaysShowCounter = ACH:Toggle(L["Always Show Counter"] or 'Always Show Counter', L["Keep the character counter visible even when the input is hidden."] or 'Keep the character counter visible even when the input is hidden.', 10, nil, nil, nil, nil, nil, function()
		return not E.db.detachat.showCounter
	end)

	-- Layering controls help the input appear above/below other UI elements.
	local layering = ACH:Group(L["Layering"] or 'Layering', nil, 20, nil, nil, nil, IsDisabled)
	options.args.layering = layering
	layering.inline = true

	layering.args.strata = ACH:Select(L["Frame Strata"] or 'Frame Strata', nil, 1, D.StrataValues)
	layering.args.level = ACH:Range(L["Frame Level"] or 'Frame Level', nil, 2, { min = 1, max = 20, step = 1 })

	-- Hide/disable the stock ElvUI option to avoid conflicting anchors.
	D:DisableElvUIEditBoxOptions()
end

-- Register the plugin with ElvUI so options are injected when ElvUI_Options loads.
local function EnsurePluginsGroup()
	if not (E and E.Options and E.Options.args) then return end

	-- Build the Plugins root group if ElvUI_Options loaded without any plugins.
	if not E.Options.args.plugins then
		local title = (EL and EL["Plugins"]) or 'Plugins'
		E.Options.args.plugins = ACH:Group(title, nil, 5)
		E.Options.args.plugins.args.pluginheader = ACH:Header(title, 1)
		E.Options.args.plugins.args.plugins = ACH:Description('', 2)
		return
	end

	-- Ensure the description node exists so LibElvUIPlugin can update it.
	if not E.Options.args.plugins.args then
		E.Options.args.plugins.args = {}
	end

	if not E.Options.args.plugins.args.plugins then
		E.Options.args.plugins.args.plugins = ACH:Description('', 2)
	end
end

local function RegisterPlugin()
	-- If options are already loaded, ensure the Plugins group exists.
	if C_AddOns.IsAddOnLoaded('ElvUI_Options') then
		EnsurePluginsGroup()
	end

	-- Avoid double-registering if another loader already did it.
	if EP.plugins and EP.plugins[ADDON_NAME] then return end

	EP:RegisterPlugin(ADDON_NAME, D.AddOptions)
end

RegisterPlugin()
