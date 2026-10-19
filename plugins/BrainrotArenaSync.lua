--!strict
--[[
	BrainrotArenaSync — Studio PLUGIN for the Brainrot Arena HUB only.

	UPDATE your local plugin (replace Plugins/BrainrotArenaSync.lua):
	  1. Create a Script, paste THIS file
	  2. Right-click → Save as Local Plugin… into Roblox/Plugins
	  3. Delete the temp Script; restart Studio if needed

	Use: open Brainrot Arena hub → Plugins → Brainrot Arena → Sync from GitHub

	v10: includes ShooterRotation (19 files). Old plugins synced 18 and froze
	GameServer waiting for ShooterRotation — hub looked empty.
]]

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local REPO = "cjd53172-dotcom/brainrot-arena"
local BRANCH = "main"
local PLUGIN_VERSION = "10-edit"

if not plugin then
	warn("[BrainrotSync] This is a PLUGIN. Delete it from ServerScriptService.")
	return
end

-- { github path under /src/, install path, instance name, class }
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
	{ "ServerScriptService/Systems/WanderSystem.lua", "ServerScriptService/Systems", "WanderSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/SoundSystem.lua", "ServerScriptService/Systems", "SoundSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/WeatherSystem.lua", "ServerScriptService/Systems", "WeatherSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/AchievementSystem.lua", "ServerScriptService/Systems", "AchievementSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/LeaderboardSystem.lua", "ServerScriptService/Systems", "LeaderboardSystem", "ModuleScript" },
	{ "ServerScriptService/Systems/WorldDesign.lua", "ServerScriptService/Systems", "WorldDesign", "ModuleScript" },
	{ "ServerScriptService/Systems/ShooterRotation.lua", "ServerScriptService/Systems", "ShooterRotation", "ModuleScript" },
	{ "ServerScriptService/GameServer.lua", "ServerScriptService", "GameServer", "Script" },
	{ "StarterPlayerScripts/ClientUI.lua", "StarterPlayer/StarterPlayerScripts", "ClientUI", "LocalScript" },
}

local toolbar = plugin:CreateToolbar("Brainrot Arena")
local button = toolbar:CreateButton(
	"Sync from GitHub",
	"Pull hub game scripts from main (includes ShooterRotation)",
	"rbxassetid://6031094678"
)
button.ClickableWhenViewportHidden = true

local function getParent(installPath: string): Instance
	local parts = string.split(installPath, "/")
	local current: Instance
	if parts[1] == "ReplicatedStorage" then
		current = ReplicatedStorage
	elseif parts[1] == "ServerScriptService" then
		current = ServerScriptService
	elseif parts[1] == "StarterPlayer" then
		current = StarterPlayer
	else
		error("Unknown root " .. parts[1])
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

local function latestSha(): string
	local url = "https://api.github.com/repos/" .. REPO .. "/commits/" .. BRANCH
	local ok, body = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if ok and type(body) == "string" then
		local decoded = HttpService:JSONDecode(body)
		if type(decoded) == "table" and type(decoded.sha) == "string" then
			return string.sub(decoded.sha, 1, 7)
		end
	end
	return BRANCH
end

local function fetch(path: string, sha: string): string?
	local url = "https://raw.githubusercontent.com/"
		.. REPO
		.. "/"
		.. BRANCH
		.. "/src/"
		.. path
		.. "?t="
		.. tostring(os.time())
		.. "&sha="
		.. sha
	local ok, result = pcall(function()
		return HttpService:GetAsync(url)
	end)
	if not ok or type(result) ~= "string" or #result < 80 then
		warn("[BrainrotSync] fetch failed " .. path .. ": " .. tostring(result))
		return nil
	end
	return result
end

local function install(installPath: string, name: string, className: string, source: string)
	local parent = getParent(installPath)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local inst = Instance.new(className)
	inst.Name = name
	;(inst :: any).Source = source
	inst.Parent = parent
	print("[BrainrotSync] " .. name .. " (" .. tostring(#source) .. " chars)")
end

local function sync()
	print("[BrainrotSync] Plugin " .. PLUGIN_VERSION .. " syncing " .. tostring(#FILES) .. " files from " .. BRANCH .. "...")
	local sha = latestSha()
	local failed = 0
	for _, entry in ipairs(FILES) do
		local source = fetch(entry[1], sha)
		if not source then
			failed += 1
		else
			install(entry[2], entry[3], entry[4], source)
		end
		task.wait(0.05)
	end

	local systems = ServerScriptService:FindFirstChild("Systems")
	if not (systems and systems:FindFirstChild("ShooterRotation")) then
		warn("[BrainrotSync] ShooterRotation still missing after sync!")
	else
		print("[BrainrotSync] ShooterRotation OK")
	end

	if failed > 0 then
		warn("[BrainrotSync] " .. tostring(failed) .. " file(s) failed")
	else
		print("[BrainrotSync] Done — all " .. tostring(#FILES) .. " files from " .. sha .. ". Save (Ctrl+S), then Play.")
	end
end

button.Click:Connect(function()
	local ok, err = pcall(sync)
	if not ok then
		warn("[BrainrotSync] error: " .. tostring(err))
	end
end)

print("[BrainrotSync] Plugin " .. PLUGIN_VERSION .. " loaded. Plugins tab -> Sync from GitHub, then Play.")
