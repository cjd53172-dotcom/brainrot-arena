--[[
	XSFArenaBoot — FFA match rules for the XSF Shooter Arena place.

	  • Double health (200 MaxHealth)
	  • leaderstats: Kills / Deaths / Unlocks (HUD reads these)
	  • Bigger starter loadout (5 hotbar weapons, includes sniper)
	  • Kill milestones unlock extra guns (kept on respawn)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local TextChat = game:GetService("TextChatService")

print("[XSFArenaBoot] waiting for XSFUnpack...")

local MAX_HEALTH = 200

-- First five sit on number keys 1–5. Slot 4 is a sniper (not knife).
local STARTER = { "HK416", "MP5", "USP", "R700", "M67" }

-- Session kills → unlock weapon (added to loadout + given mid-life).
local UNLOCKS = {
	{ Kills = 2, Weapon = "AK47", Label = "AK-47" },
	{ Kills = 4, Weapon = "M870", Label = "Shotgun" },
	{ Kills = 6, Weapon = "Deagle", Label = "Desert Eagle" },
	{ Kills = 8, Weapon = "AWM", Label = "AWM Sniper" },
	{ Kills = 10, Weapon = "RPG7", Label = "RPG-7" },
	{ Kills = 12, Weapon = "M249", Label = "M249" },
}

local sessionKills = {} -- [userId] = number
local unlocked = {} -- [userId] = { [weaponName] = true }

-- Remove old floating world board if a previous sync left one behind.
local oldBoard = workspace:FindFirstChild("XSFScoreboard")
if oldBoard then
	oldBoard:Destroy()
end

local function log(msg)
	print("[XSFArenaBoot] " .. msg)
end

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

log("XSF folders found — loading match rules")

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
	warn("[XSFArenaBoot] XSF API not ready — health/scoreboard still apply; guns need XSF.Server")
end

local function ensureLeaderstats(player)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		ls.Parent = player
	end
	local function ensureStat(name)
		local s = ls:FindFirstChild(name)
		if not (s and (s:IsA("IntValue") or s:IsA("NumberValue"))) then
			if s then
				s:Destroy()
			end
			s = Instance.new("IntValue")
			s.Name = name
			s.Value = 0
			s.Parent = ls
		end
		return s
	end
	return ensureStat("Kills"), ensureStat("Deaths"), ensureStat("Unlocks")
end

local function loadoutFor(player)
	local list = {}
	for _, name in ipairs(STARTER) do
		table.insert(list, name)
	end
	local owned = unlocked[player.UserId] or {}
	for _, row in ipairs(UNLOCKS) do
		if owned[row.Weapon] then
			table.insert(list, row.Weapon)
		end
	end
	return list
end

local function announce(player, text)
	pcall(function()
		if TextChat.ChatVersion == Enum.ChatVersion.TextChatService then
			local channels = TextChat:FindFirstChild("TextChannels")
			local sys = channels and channels:FindFirstChild("RBXSystem")
			if sys and sys:IsA("TextChannel") then
				sys:DisplaySystemMessage(text)
				return
			end
		end
	end)
	-- Fallback: attribute toast other UIs can read; also print.
	player:SetAttribute("XSFUnlockMsg", text)
	log(text)
end

local function applyHealth(char)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 8)
	if not (hum and hum:IsA("Humanoid")) then
		return
	end
	local function setHp(full)
		if not hum.Parent then
			return
		end
		hum.MaxHealth = MAX_HEALTH
		if full or hum.Health <= 0 then
			hum.Health = MAX_HEALTH
		elseif hum.Health > MAX_HEALTH then
			hum.Health = MAX_HEALTH
		end
	end
	setHp(true)
	-- XSF character setup can reset MaxHealth — re-assert after it settles.
	task.delay(0.5, function()
		setHp(true)
	end)
	task.delay(2, function()
		setHp(false)
	end)
end

local function giveLoadout(player)
	if not XSF then
		return
	end
	local list = loadoutFor(player)
	local ok, err = pcall(function()
		XSF.SetLoadout(player, list)
	end)
	if not ok then
		warn("[XSFArenaBoot] SetLoadout failed: " .. tostring(err))
	end
end

local function grantUnlock(player, weapon, label, midLife)
	local uid = player.UserId
	unlocked[uid] = unlocked[uid] or {}
	if unlocked[uid][weapon] then
		return false
	end
	unlocked[uid][weapon] = true
	local _, _, unlockStat = ensureLeaderstats(player)
	unlockStat.Value = unlockStat.Value + 1
	announce(player, player.Name .. " unlocked " .. (label or weapon) .. "!")
	if midLife and XSF and type(XSF.Give) == "function" then
		pcall(function()
			XSF.Give(player, weapon)
		end)
	end
	return true
end

local function checkUnlocks(player, kills, midLife)
	for _, row in ipairs(UNLOCKS) do
		if kills >= row.Kills then
			grantUnlock(player, row.Weapon, row.Label, midLife)
		end
	end
end

local function onCharacter(player, char)
	ensureLeaderstats(player)
	applyHealth(char)
	task.delay(1, function()
		if player.Parent and char.Parent then
			giveLoadout(player)
		end
	end)
end

local function setupPlayer(player)
	sessionKills[player.UserId] = sessionKills[player.UserId] or 0
	unlocked[player.UserId] = unlocked[player.UserId] or {}
	local killsStat, _, unlockStat = ensureLeaderstats(player)
	killsStat.Value = sessionKills[player.UserId]
	local n = 0
	for _ in pairs(unlocked[player.UserId]) do
		n = n + 1
	end
	unlockStat.Value = n
	checkUnlocks(player, sessionKills[player.UserId], false)

	player.CharacterAdded:Connect(function(char)
		onCharacter(player, char)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
end

Players.PlayerAdded:Connect(setupPlayer)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(setupPlayer, player)
end

Players.PlayerRemoving:Connect(function(player)
	sessionKills[player.UserId] = nil
	unlocked[player.UserId] = nil
end)

local function bumpKill(attacker)
	if not attacker then
		return
	end
	local uid = attacker.UserId
	sessionKills[uid] = (sessionKills[uid] or 0) + 1
	local killsStat = ensureLeaderstats(attacker)
	killsStat.Value = sessionKills[uid]
	checkUnlocks(attacker, sessionKills[uid], true)
end

local function bumpDeath(victimPlayer)
	if not victimPlayer then
		return
	end
	local _, deathsStat = ensureLeaderstats(victimPlayer)
	deathsStat.Value = deathsStat.Value + 1
end

if XSF and XSF.Killed then
	XSF.Killed:Connect(function(victimHum, attacker, _weapon)
		local victimModel = victimHum and victimHum.Parent
		local victimPlayer = victimModel and Players:GetPlayerFromCharacter(victimModel)
		if victimPlayer then
			bumpDeath(victimPlayer)
		end
		if attacker and attacker:IsA("Player") and attacker ~= victimPlayer then
			bumpKill(attacker)
		end
	end)
	log("hooked XSF.Killed for scoreboard + unlocks")
else
	-- Fallback if API has no Killed signal yet.
	local function hookDied(player, char)
		local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 8)
		if not (hum and hum:IsA("Humanoid")) then
			return
		end
		hum.Died:Connect(function()
			bumpDeath(player)
			local tag = hum:FindFirstChild("creator") or hum:FindFirstChild("Creator")
			if tag and tag:IsA("ObjectValue") and tag.Value then
				local killer = tag.Value
				if killer:IsA("Player") then
					bumpKill(killer)
				elseif killer:IsA("Model") then
					local kp = Players:GetPlayerFromCharacter(killer)
					if kp then
						bumpKill(kp)
					end
				end
			end
		end)
	end
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			hookDied(player, char)
		end)
		if player.Character then
			hookDied(player, player.Character)
		end
	end)
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			hookDied(player, player.Character)
		end
	end
	warn("[XSFArenaBoot] XSF.Killed missing — using Humanoid.Died fallback")
end

log(
	"ready — HP "
		.. tostring(MAX_HEALTH)
		.. " | starter "
		.. table.concat(STARTER, ", ")
		.. " | "
		.. tostring(#UNLOCKS)
		.. " unlock guns | HUD scoreboard"
)
