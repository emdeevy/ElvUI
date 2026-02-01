local ADDON_NAME = ...
local E = unpack(ElvUI)

-- Define the base locale. Other locales can replace/extend these keys.
local L = E.Libs.ACL:NewLocale(ADDON_NAME, 'enUS', true, true)
if not L then return end

L["Detachat"] = true
L["DETACHAT_DESC"] = "Detach the chat input so it can be freely moved with a mover."
L["Chat Input"] = true
L["Enable"] = true
L["Size & Position"] = true
L["Match Chat Panel Width"] = true
L["Match the input width to the selected chat panel."] = true
L["Chat Panel"] = true
L["Which chat panel to match when syncing width."] = true
L["Left"] = true
L["Right"] = true
L["Width"] = true
L["Height"] = true
L["Padding"] = true
L["Inset the input within the holder."] = true
L["Layering"] = true
L["Frame Strata"] = true
L["Frame Level"] = true
L["Detachat manages the chat input position."] = true
L["Always Show Counter"] = true
L["Keep the character counter visible even when the input is hidden."] = true
L["Always Show Input"] = true
L["Keep the chat input visible even when it is not focused."] = true
L["Hide When Unfocused"] = true
L["Hide the chat input when it is not focused (overrides classic behavior)."] = true
L["Prevent Tab Auto Focus"] = true
L["Keep the chat input from auto-focusing when switching tabs."] = true
L["Show Counter"] = true
L["Display the character counter frame next to the input."] = true
