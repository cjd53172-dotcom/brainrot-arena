--!strict
--[[
	GameLoader (Script -> ServerScriptService)
	ONE-TIME PASTE. This is the only script you ever manually install.

	On every server start, it downloads the latest game code from GitHub
	and builds the full script tree automatically:
	  ReplicatedStorage/BrainrotData (ModuleScript)
	  ServerScriptService/Systems/{PlayerData,QuestSystem,PlotSystem,BattleSystem} (ModuleScripts)
	  ServerScriptService/GameServer (Script) -- runs the game
	  StarterPlayer/StarterPlayerScripts/ClientUI (LocalScript)

	Requirements (one-time, in Studio):
	  1. Game Settings -> Security -> Enable HTTP Requests = ON

	To update the game: just push new code to GitHub and restart the server.
	No more pasting files!
]]

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

-- !!! REPLACE THIS with your GitHub repo raw URL !!!
-- Format: https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/src/
local BASE_URL = "https://raw.githubusercontent.com/cjd53172-dotcom/brainrot-arena/main/src/"

-- { github path, where to install, instance name, class }
local FILES: { { string } } = {
	{ "ReplicatedStorage/BrainrotData.lua", "ReplicatedStorage", "BrainrotData", "ModuleScript" },
	{ "ServerScriptService/Systems/PlayerData.lua", "ServerScriptService/Systems", "PlayerData", "ModuleScript" },
	{ "ServerScriptService/Systems/QuestSystem.lua", "ServerScriptService/Systems", "QuestSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/PlotSystem.lua", "ServerScriptService/Systems", "PlotSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/BattleSystem.lua", "ServerScriptService/Systems", "BattleSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/ExpeditionSystem.lua", "ServerScriptService/Systems", "ExpeditionSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/DailyQuestSystem.lua", "ServerScriptService/Systems", "DailyQuestSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/EggSystem.lua", "ServerScriptService/Systems", "EggSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/VisualEffects.lua", "ServerScriptService/Systems", "VisualEffects", "ModuleScript" },
	{ "ServerScriptService/Systems/FishingSystem.lua", "ServerScriptService/Systems", "FishingSystem", "ModuleScript" },
	{ "ServerScriptService/GameServer.lua", "ServerScriptService", "GameServer", "Script" },
	{ "StarterPlayerScripts/ClientUI.lua", "StarterPlayer/StarterPlayerScripts", "ClientUI", "LocalScript" },
}

local function getService(path: string): Instance
	-- "ServerScriptService/Systems" -> the Systems folder (create if missing)
	local parts = string.split(path, "/")
	local current: Instance
	if parts[1] == "ReplicatedStorage" then
		current = ReplicatedStorage
	elseif parts[1] == "ServerScriptService" then
		current = ServerScriptService
	elseif parts[1] == "StarterPlayer" then
		current = StarterPlayer
	else
		error("[GameLoader] Unknown root: " .. parts[1])
	end
	for i = 2, #parts do
		local child = current:FindFirstChild(parts[i])
		if not child then
			child = Instance.new("Folder")
			child.Name = parts[i]
			child.Parent = current
		end
		current = child
	end
	return current
end

local function fetchSource(urlPath: string): string?
	local url = BASE_URL .. urlPath
	local ok, result = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not ok then
		warn("[GameLoader] HTTP failed for " .. urlPath .. ": " .. tostring(result))
		return nil
	end
	if type(result) ~= "string" or #result < 100 then
		warn("[GameLoader] Suspiciously short file for " .. urlPath .. " (" .. tostring(#(result or "")) .. " chars)")
		return nil
	end
	return result
end

-- Install order matters: modules before the scripts that require them.
-- GameServer (Script) goes last so it starts after all modules exist.
-- ClientUI (LocalScript) can go any time before players join.
local installOrder = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 11 }

print("[GameLoader] Installing Brainrot Arena from " .. BASE_URL)
local failed = 0
for _, idx in ipairs(installOrder) do
	local entry = FILES[idx]
	local urlPath, installPath, instName, className = entry[1], entry[2], entry[3], entry[4]
	local source = fetchSource(urlPath)
	if not source then
		failed += 1
	else
		local parent = getService(installPath)
		-- Remove stale copy (except ourselves).
		local old = parent:FindFirstChild(instName)
		if old and old ~= script then
			old:Destroy()
		end
		local inst = Instance.new(className)
		inst.Name = instName
		-- Setting Source on a fresh Script/ModuleScript/LocalScript makes it live.
		(inst :: any).Source = source
		inst.Parent = parent
		print("[GameLoader] Installed " .. instName .. " (" .. #source .. " chars)")
	end
	task.wait(0.1) -- be gentle with the HTTP queue
end

if failed > 0 then
	warn("[GameLoader] " .. tostring(failed) .. " files FAILED to install. Game may not start correctly.")
else
	print("[GameLoader] All files installed. GameServer should now be running.")
end

-- Edge case: players who were already in the game before ClientUI was
-- installed (e.g. Studio Play Solo) won't get it via StarterPlayerScripts.
-- Clone it directly into their PlayerScripts.
pcall(function()
	local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
	local clientUI = sps and sps:FindFirstChild("ClientUI")
	if clientUI then
		for _, player in ipairs(Players:GetPlayers()) do
			local ps = player:FindFirstChild("PlayerScripts")
			if ps and not ps:FindFirstChild("ClientUI") then
				clientUI:Clone().Parent = ps
				print("[GameLoader] Patched ClientUI for " .. player.Name)
			end
		end
	end
end)

print("[GameLoader] Done. This loader stays in ServerScriptService and re-runs on every server start.")
