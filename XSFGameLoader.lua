--!strict
--[[
	DEPRECATED as a runtime installer.

	Roblox no longer allows Scripts to write other scripts' .Source at Play
	time (PluginOrOpenCloud only). Use the Studio PLUGIN instead:

	  plugins/XSFSync.lua  →  Save as Local Plugin
	  Then: Plugins → "XSF Sync from GitHub"  (in the XSF place only)

	If this Script is still in ServerScriptService, it just prints that tip
	and removes itself so it does not spam errors.
]]

warn("[XSFGameLoader] Runtime GitHub install is blocked by Roblox (cannot write Source).")
warn("[XSFGameLoader] Use Plugins → XSF Sync from GitHub instead (install plugins/XSFSync.lua as a Local Plugin).")
warn("[XSFGameLoader] Do NOT use Brainrot Arena → Sync from GitHub in this place.")

-- Clean up duplicate broken loaders
local sss = game:GetService("ServerScriptService")
for _, name in ipairs({ "XSFGameLoader", "XSFGameLoaderlua" }) do
	local inst = sss:FindFirstChild(name)
	if inst and inst ~= script then
		inst:Destroy()
	end
end

if script.Parent then
	script:Destroy()
end
