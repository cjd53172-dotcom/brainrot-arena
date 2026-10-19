--!strict
--[[
	Paste into ServerScriptService of the XSF Shooter Arena PLACE
	(alongside XSFReturn — after the real XSF framework is installed).

	WHY THERE ARE NO GUNS YET
	========================
	XSF ships as Workspace.XSF_Release. That folder is only a package.
	Guns do not work until you move its insides into the matching services:

	  XSF_Release/ReplicatedStorage/XSF     →  ReplicatedStorage/XSF
	  XSF_Release/ServerScriptService/XSF   →  ServerScriptService/XSF
	  XSF_Release/StarterPlayerScripts/XSF_Boot
	                                        →  StarterPlayer.StarterPlayerScripts/XSF_Boot

	Then delete the empty XSF_Release folder.
	Home → Game Settings → Security → Allow HTTP Requests = ON (XSF license).

	Do NOT put the XSF kit itself on GitHub — it is license-tied to your
	XSF account. Keep only our Arena glue (this script + XSFReturn) in git.

	This script:
	1. Warns in Output if XSF is still packaged / missing.
	2. After XSF boots, sets a simple deathmatch loadout.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

print("[XSFArenaBoot] checking XSF install...")

local function warnInstall(msg: string)
	warn("[XSFArenaBoot] " .. msg)
end

-- Detect the common "still in the package folder" mistake.
local packaged = workspace:FindFirstChild("XSF_Release")
if packaged then
	local nestedRS = packaged:FindFirstChild("ReplicatedStorage")
	local nestedXSF = nestedRS and nestedRS:FindFirstChild("XSF")
	if nestedXSF then
		warnInstall("XSF_Release is still in Workspace with XSF inside it. Drag XSF out of XSF_Release/ReplicatedStorage into ReplicatedStorage, then do the same for ServerScriptService and StarterPlayerScripts. Delete empty XSF_Release when done.")
	end
end

local rsXSF = ReplicatedStorage:FindFirstChild("XSF")
local sssXSF = ServerScriptService:FindFirstChild("XSF")
local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
local boot = sps and sps:FindFirstChild("XSF_Boot")

if not rsXSF then
	warnInstall("Missing ReplicatedStorage.XSF — guns will not load.")
end
if not sssXSF then
	warnInstall("Missing ServerScriptService.XSF — guns will not load.")
end
if not boot then
	warnInstall("Missing StarterPlayer.StarterPlayerScripts.XSF_Boot — clients will not start XSF.")
end

if not (rsXSF and sssXSF) then
	warnInstall("Fix the install steps above, publish this place, then Play again.")
	return
end

-- Official server API: require(ServerScriptService.XSF.Server)
local XSF: any = nil
local deadline = os.clock() + 45
while os.clock() < deadline do
	local folder = ServerScriptService:FindFirstChild("XSF")
	local serverMod = folder and folder:FindFirstChild("Server")
	if serverMod and serverMod:IsA("ModuleScript") then
		local ok, api = pcall(require, serverMod)
		if ok and type(api) == "table" and type(api.SetLoadout) == "function" then
			XSF = api
			break
		end
	end
	task.wait(0.5)
end

if not XSF then
	print("[XSFArenaBoot] XSF folders look installed — relying on GameConfig.Loadout. If you still have no gun, open ReplicatedStorage.XSF.GameConfig and set Loadout = { \"HK416\", \"USP\", \"M67\" }")
	return
end

-- Arcade deathmatch kit (names must match folders in ReplicatedStorage.XSF.Weapons).
local LOADOUT = { "HK416", "USP", "M67" }

local function give(player: Player)
	local ok, err = pcall(function()
		XSF.SetLoadout(player, LOADOUT)
	end)
	if not ok then
		warn("[XSFArenaBoot] SetLoadout failed for " .. player.Name .. ": " .. tostring(err))
	end
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(1)
		if player.Parent then
			give(player)
		end
	end)
	if player.Character then
		task.spawn(function()
			task.wait(1)
			give(player)
		end)
	end
end)

for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(function()
		task.wait(1)
		give(player)
	end)
end

print("[XSFArenaBoot] ready — loadout " .. table.concat(LOADOUT, ", "))
