--[[
	XSFArenaBoot — waits for XSFUnpack, then sets FFA loadout via XSF API.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

print("[XSFArenaBoot] waiting for XSFUnpack...")

local function waitForXSF(seconds)
	local deadline = os.clock() + seconds
	while os.clock() < deadline do
		local rs = ReplicatedStorage:FindFirstChild("XSF")
		local sss = ServerScriptService:FindFirstChild("XSF")
		local sps = StarterPlayer:FindFirstChild("StarterPlayerScripts")
		local boot = sps and sps:FindFirstChild("XSF_Boot")
		if rs and sss and boot then
			return true
		end
		task.wait(0.2)
	end
	return false
end

if not waitForXSF(20) then
	warn("[XSFArenaBoot] XSF still missing after wait. Keep Workspace.XSF_Release and XSFUnpack, then Play again.")
	return
end

print("[XSFArenaBoot] XSF folders found — requesting loadout")

local XSF = nil
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
	print("[XSFArenaBoot] XSF API not ready — use GameConfig.Loadout = { \"HK416\", \"USP\", \"M67\" }")
	return
end

local LOADOUT = { "HK416", "USP", "M67" }

local function give(player)
	local ok, err = pcall(function()
		XSF.SetLoadout(player, LOADOUT)
	end)
	if not ok then
		warn("[XSFArenaBoot] SetLoadout failed: " .. tostring(err))
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
