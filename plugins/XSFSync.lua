--!strict
--[[
	XSFSync — Studio PLUGIN for the XSF Shooter Arena place only.

	Install / update plugin:
	  1. Create a Script, paste THIS whole file
	  2. Right-click → Save as Local Plugin… (into Roblox/Plugins)
	  3. Delete the temporary Script
	  4. Restart Studio if needed

	Use in XSF place: Plugins → XSF Sync from GitHub → Play
]]

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local HUB_PLACE_ID = 92909397469421
local XSF_PLACE_ID = 105098537406613
-- Always pull from main so Merge → Sync works (do not pin a PR branch).
local GIT_REF = "main"
local BASE_URL = "https://raw.githubusercontent.com/cjd53172-dotcom/brainrot-arena/" .. GIT_REF .. "/src/"

-- New FFA script name so a stale XSFExpandArena cannot stick around.
local FILES: { { string } } = {
	{ "Minigames/XSFUnpack.lua", "XSFUnpack" },
	{ "Minigames/XSFReturn.lua", "XSFReturn" },
	{ "Minigames/XSFArenaBoot.lua", "XSFArenaBoot" },
	{ "Minigames/XSFArenaFFA.lua", "XSFArenaFFA" },
}

if not plugin then
	warn("[XSFSync] This file is a PLUGIN. Delete it from ServerScriptService.")
	return
end

local toolbar = plugin:CreateToolbar("XSF Shooter")
local button = toolbar:CreateButton(
	"XSF Sync from GitHub",
	"Pull XSF glue scripts only (not Brainrot hub)",
	"rbxassetid://6031094678"
)
button.ClickableWhenViewportHidden = true

local function fetch(path: string): string?
	local url = BASE_URL .. path .. "?t=" .. tostring(os.time()) .. "&v=4"
	local ok, result = pcall(function()
		return HttpService:GetAsync(url)
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
	scr.Enabled = true
	scr.Parent = ServerScriptService
	local marker = string.sub(source, 1, 40)
	print("[XSFSync] installed " .. name .. " (" .. tostring(#source) .. " chars) start=" .. marker)
end

local function sync()
	print("[XSFSync] PlaceId=" .. tostring(game.PlaceId) .. " ref=" .. GIT_REF)

	if game.PlaceId == HUB_PLACE_ID then
		warn("[XSFSync] Hub place — use Brainrot Arena plugin, not XSF Sync.")
		return
	end

	local junkNames = {
		"XSFGameLoader",
		"XSFGameLoaderlua",
		"GameLoader",
		"GameServer",
		"XSFSync",
		"ClientUI",
		"Portal",
		"Systems",
		"XSFExpandArena", -- old broken script — replaced by XSFArenaFFA
	}
	for _, name in ipairs(junkNames) do
		local junk = ServerScriptService:FindFirstChild(name)
		if junk then
			warn("[XSFSync] removing " .. name)
			junk:Destroy()
		end
	end

	local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	if sps then
		local cui = sps:FindFirstChild("ClientUI")
		if cui then
			warn("[XSFSync] removing hub ClientUI")
			cui:Destroy()
		end
	end
	local bd = game:GetService("ReplicatedStorage"):FindFirstChild("BrainrotData")
	if bd then
		bd:Destroy()
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

	local names = {}
	for _, child in ipairs(ServerScriptService:GetChildren()) do
		table.insert(names, child.Name)
	end
	print("[XSFSync] ServerScriptService now has: " .. table.concat(names, ", "))

	if not ServerScriptService:FindFirstChild("XSFArenaFFA") then
		warn("[XSFSync] XSFArenaFFA MISSING — sync failed. Check HTTP Requests.")
	end

	if failed > 0 then
		warn("[XSFSync] " .. tostring(failed) .. " file(s) failed")
	else
		print("[XSFSync] Done. Confirm Explorer shows XSFArenaFFA, then Press Play.")
	end
end

button.Click:Connect(function()
	local ok, err = pcall(sync)
	if not ok then
		warn("[XSFSync] error: " .. tostring(err))
	end
end)

print("[XSFSync] Plugin loaded (v4 — pulls main). Plugins → XSF Sync from GitHub.")
