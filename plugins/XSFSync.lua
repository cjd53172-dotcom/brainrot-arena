--!strict
--[[
	XSFSync — Studio PLUGIN for the XSF Shooter Arena place only.

	Install once:
	  1. In Studio (any place), create a Script, paste THIS whole file
	  2. Right-click the Script → Save as Local Plugin…
	  3. Delete the temporary Script from the place
	  4. Restart Studio if the toolbar button does not appear

	Use:
	  Open XSF Shooter Arena → Plugins tab → "XSF Sync from GitHub"
	  Then press Play.

	This does NOT pull Brainrot hub code. Use the separate "Brainrot Arena"
	plugin only in the hub place.
]]

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")
local Selection = game:GetService("Selection")

local HUB_PLACE_ID = 92909397469421
local XSF_PLACE_ID = 105098537406613
local GIT_REF = "cursor/shooter-portal-cycle-9893"
local BASE_URL = "https://raw.githubusercontent.com/cjd53172-dotcom/brainrot-arena/" .. GIT_REF .. "/src/"

local FILES: { { string } } = {
	{ "Minigames/XSFUnpack.lua", "XSFUnpack" },
	{ "Minigames/XSFReturn.lua", "XSFReturn" },
	{ "Minigames/XSFArenaBoot.lua", "XSFArenaBoot" },
	{ "Minigames/XSFExpandArena.lua", "XSFExpandArena" },
}

local toolbar = plugin:CreateToolbar("XSF Shooter")
local button = toolbar:CreateButton(
	"XSF Sync from GitHub",
	"Pull XSF glue scripts only (not Brainrot hub)",
	"rbxassetid://6031094678"
)
button.ClickableWhenViewportHidden = true

local function fetch(path: string): string?
	local ok, result = pcall(function()
		return HttpService:GetAsync(BASE_URL .. path)
	end)
	if not ok or type(result) ~= "string" or #result < 80 then
		warn("[XSFSync] failed to fetch " .. path .. ": " .. tostring(result))
		return nil
	end
	return result
end

local function install(name: string, source: string)
	local old = ServerScriptService:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local scr = Instance.new("Script")
	scr.Name = name
	scr.Source = source
	scr.Parent = ServerScriptService
	print("[XSFSync] installed " .. name .. " (" .. tostring(#source) .. " chars)")
end

local function sync()
	local placeId = game.PlaceId
	print("[XSFSync] PlaceId=" .. tostring(placeId) .. " ref=" .. GIT_REF)

	if placeId == HUB_PLACE_ID then
		warn("[XSFSync] You are in Brainrot Arena hub. Use the Brainrot Arena plugin here, not XSF Sync.")
		return
	end
	if placeId ~= 0 and placeId ~= XSF_PLACE_ID then
		warn("[XSFSync] Unexpected place " .. tostring(placeId) .. " — expected XSF " .. tostring(XSF_PLACE_ID) .. ". Syncing XSF glue anyway.")
	end

	-- Remove duplicate broken loaders that try (and fail) to write Source at runtime
	for _, name in ipairs({ "XSFGameLoader", "XSFGameLoaderlua", "GameLoader", "GameServer" }) do
		local junk = ServerScriptService:FindFirstChild(name)
		if junk then
			warn("[XSFSync] removing " .. name .. " (runtime Source writes are blocked; use this plugin instead)")
			junk:Destroy()
		end
	end

	local failed = 0
	for _, entry in ipairs(FILES) do
		local source = fetch(entry[1])
		if not source then
			failed += 1
		else
			install(entry[2], source)
		end
		task.wait(0.05)
	end

	if failed > 0 then
		warn("[XSFSync] " .. tostring(failed) .. " file(s) failed. Check HTTP is allowed in Game Settings → Security.")
	else
		print("[XSFSync] Done. Press Play — FFA arena, 5 spawns, 5 return portals. Hub code was NOT pulled.")
	end
end

button.Click:Connect(function()
	local ok, err = pcall(sync)
	if not ok then
		warn("[XSFSync] error: " .. tostring(err))
	end
end)

print("[XSFSync] Plugin loaded. Open XSF Shooter Arena → Plugins → XSF Sync from GitHub.")
