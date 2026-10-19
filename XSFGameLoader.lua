--!strict
--[[
	XSFGameLoader (Script → ServerScriptService of the XSF Shooter Arena PLACE ONLY)

	ONE-TIME PASTE into the XSF place — never into Brainrot Arena.

	Pulls ONLY the XSF glue scripts from GitHub. It will NOT install
	Brainrot hub systems (GameServer, plots, ClientUI, BrainrotData, …).

	Installed each server start:
	  ServerScriptService/XSFUnpack
	  ServerScriptService/XSFReturn
	  ServerScriptService/XSFArenaBoot
	  ServerScriptService/XSFExpandArena

	Requirements:
	  1. Open the XSF Shooter Arena place (not the hub)
	  2. Game Settings → Security → Allow HTTP Requests = ON
	  3. Paste this script once; keep it; publish

	Updates: push to GitHub, restart the XSF server (or Play again).

	Optional Workspace attribute:
	  XSFGitRef = "main"   -- or a branch name while testing a PR
]]

local HttpService = game:GetService("HttpService")
local ServerScriptService = game:GetService("ServerScriptService")

local HUB_PLACE_ID = 92909397469421
local XSF_PLACE_ID = 105098537406613

print("[XSFGameLoader] PlaceId=" .. tostring(game.PlaceId))

if game.PlaceId == HUB_PLACE_ID then
	warn("[XSFGameLoader] This is Brainrot Arena hub. Removing myself — use GameLoader.lua here, not XSFGameLoader.")
	script:Destroy()
	return
end

-- Soft check: warn if somehow running elsewhere, but still allow Studio unpublished (PlaceId 0)
if game.PlaceId ~= 0 and game.PlaceId ~= XSF_PLACE_ID then
	warn("[XSFGameLoader] Unexpected PlaceId " .. tostring(game.PlaceId) .. " — expected XSF " .. tostring(XSF_PLACE_ID) .. ". Continuing anyway.")
end

local gitRef = workspace:GetAttribute("XSFGitRef")
if type(gitRef) ~= "string" or gitRef == "" then
	gitRef = "main"
end

local BASE_URL = "https://raw.githubusercontent.com/cjd53172-dotcom/brainrot-arena/"
	.. tostring(gitRef)
	.. "/src/"

-- XSF-only files. Never add hub GameServer / BrainrotData here.
local FILES: { { string } } = {
	{ "Minigames/XSFUnpack.lua", "XSFUnpack", "Script" },
	{ "Minigames/XSFReturn.lua", "XSFReturn", "Script" },
	{ "Minigames/XSFArenaBoot.lua", "XSFArenaBoot", "Script" },
	{ "Minigames/XSFExpandArena.lua", "XSFExpandArena", "Script" },
}

-- Strip hub leftovers if someone pasted the wrong loader earlier.
do
	local hubJunk = {
		"GameServer",
		"GameLoader",
		"BrainrotData",
		"ClientUI",
		"Systems",
	}
	for _, name in ipairs(hubJunk) do
		local inst = ServerScriptService:FindFirstChild(name)
		if inst and inst ~= script then
			warn("[XSFGameLoader] removing hub leftover ServerScriptService." .. name)
			inst:Destroy()
		end
	end
	local rs = game:GetService("ReplicatedStorage")
	local bd = rs:FindFirstChild("BrainrotData")
	if bd then
		warn("[XSFGameLoader] removing hub leftover ReplicatedStorage.BrainrotData")
		bd:Destroy()
	end
	local sps = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
	local cui = sps and sps:FindFirstChild("ClientUI")
	if cui then
		warn("[XSFGameLoader] removing hub leftover ClientUI")
		cui:Destroy()
	end
end

local function fetchSource(urlPath: string): string?
	local url = BASE_URL .. urlPath
	local ok, result = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not ok then
		warn("[XSFGameLoader] HTTP failed for " .. urlPath .. ": " .. tostring(result))
		return nil
	end
	if type(result) ~= "string" or #result < 80 then
		warn("[XSFGameLoader] short/empty file for " .. urlPath)
		return nil
	end
	return result
end

print("[XSFGameLoader] Installing XSF glue from " .. BASE_URL)
local failed = 0
for _, entry in ipairs(FILES) do
	local urlPath, instName, className = entry[1], entry[2], entry[3]
	local source = fetchSource(urlPath)
	if not source then
		failed += 1
	else
		local old = ServerScriptService:FindFirstChild(instName)
		if old and old ~= script then
			old:Destroy()
		end
		local inst = Instance.new(className)
		inst.Name = instName
		;(inst :: any).Source = source
		inst.Parent = ServerScriptService
		-- Re-enable in case a previous Unpack run disabled a leftover copy
		if inst:IsA("BaseScript") then
			(inst :: BaseScript).Enabled = true
		end
		print("[XSFGameLoader] Installed " .. instName .. " (" .. #source .. " chars)")
	end
	task.wait(0.08)
end

if failed > 0 then
	warn("[XSFGameLoader] " .. tostring(failed) .. " file(s) failed. If ref is main before merge, set Workspace.XSFGitRef = \"cursor/shooter-portal-cycle-9893\"")
else
	print("[XSFGameLoader] XSF glue installed. Hub Brainrot code was not pulled.")
end

print("[XSFGameLoader] Done. This loader stays in the XSF place only.")
