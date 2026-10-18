--!strict
--[[
	Paste this Script into ServerScriptService of the Laser Tag PLACE
	(Whiskeandgaming's Place / Laser Tag — not the Brainrot Arena hub).

	Does two jobs:
	1. Orange return gate back to the arena.
	2. Records kills into OrderedDataStore "LaserTagKills_v1" so the plaza
	   board next to the Laser Tag portal can show them.

	After pasting: File → Publish to Roblox → overwrite THIS laser tag place only.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")

local HUB_PLACE_ID = 92909397469421
local returnPlaceByUser: { [number]: number } = {}

local killStore: OrderedDataStore? = nil
pcall(function()
	killStore = DataStoreService:GetOrderedDataStore("LaserTagKills_v1")
end)

local lastKillAt: { [number]: number } = {}
local usingLeaderstats: { [number]: boolean } = {}

local function hubIdFor(player: Player): number
	return returnPlaceByUser[player.UserId] or HUB_PLACE_ID
end

local function recordKills(player: Player, amount: number)
	if amount <= 0 then
		return
	end
	local now = os.clock()
	if lastKillAt[player.UserId] and now - lastKillAt[player.UserId] < 0.05 then
		return
	end
	lastKillAt[player.UserId] = now
	if killStore then
		pcall(function()
			(killStore :: OrderedDataStore):IncrementAsync(tostring(player.UserId), amount)
		end)
	end
end

local function killerFromHumanoid(hum: Humanoid): Player?
	local tag = hum:FindFirstChild("creator") or hum:FindFirstChild("Creator")
	if not (tag and tag:IsA("ObjectValue")) then
		return nil
	end
	local value = (tag :: ObjectValue).Value
	if value and value:IsA("Player") then
		return value
	end
	if value and value:IsA("Model") then
		return Players:GetPlayerFromCharacter(value)
	end
	return nil
end

local function hookCharacter(player: Player, char: Model)
	local hum = char:FindFirstChildOfClass("Humanoid") or char:WaitForChild("Humanoid", 8)
	if not (hum and hum:IsA("Humanoid")) then
		return
	end
	(hum :: Humanoid).Died:Connect(function()
		if usingLeaderstats[player.UserId] then
			return
		end
		local killer = killerFromHumanoid(hum :: Humanoid)
		if killer and killer ~= player then
			recordKills(killer, 1)
		end
	end)
end

local function hookLeaderstats(player: Player)
	task.spawn(function()
		local ls = player:WaitForChild("leaderstats", 12)
		if not ls then
			return
		end
		local stat = ls:FindFirstChild("Kills") or ls:FindFirstChild("Score") or ls:FindFirstChild("Points")
		if not (stat and (stat:IsA("IntValue") or stat:IsA("NumberValue"))) then
			return
		end
		usingLeaderstats[player.UserId] = true
		local last = (stat :: any).Value
		stat.Changed:Connect(function()
			local nowVal = (stat :: any).Value
			local delta = nowVal - last
			last = nowVal
			if delta > 0 then
				recordKills(player, delta)
			end
		end)
	end)
end

Players.PlayerAdded:Connect(function(player: Player)
	local join = player:GetJoinData()
	local data = join and join.TeleportData
	if type(data) == "table" and type(data.ReturnPlaceId) == "number" and data.ReturnPlaceId > 0 then
		returnPlaceByUser[player.UserId] = data.ReturnPlaceId
	end
	hookLeaderstats(player)
	player.CharacterAdded:Connect(function(char)
		hookCharacter(player, char)
	end)
	if player.Character then
		hookCharacter(player, player.Character)
	end
end)

Players.PlayerRemoving:Connect(function(player: Player)
	returnPlaceByUser[player.UserId] = nil
	usingLeaderstats[player.UserId] = nil
	lastKillAt[player.UserId] = nil
end)

for _, player in ipairs(Players:GetPlayers()) do
	hookLeaderstats(player)
	if player.Character then
		hookCharacter(player, player.Character)
	end
end

local gate = Instance.new("Part")
gate.Name = "ReturnToArena"
gate.Size = Vector3.new(8, 12, 2)
gate.Anchored = true
gate.CanCollide = false
gate.Color = Color3.fromRGB(255, 180, 40)
gate.Material = Enum.Material.Neon
gate.Position = Vector3.new(0, 8, 0)
gate.Parent = workspace

local prompt = Instance.new("ProximityPrompt")
prompt.ActionText = "Return"
prompt.ObjectText = "Brainrot Arena"
prompt.HoldDuration = 0
prompt.MaxActivationDistance = 16
prompt.RequiresLineOfSight = false
prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
prompt.KeyboardKeyCode = Enum.KeyCode.E
prompt.Parent = gate

local function goHome(player: Player)
	local placeId = hubIdFor(player)
	if placeId <= 0 then
		return
	end
	pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
end

prompt.Triggered:Connect(goHome)
gate.Touched:Connect(function(hit: BasePart)
	local char = hit and hit.Parent
	local player = char and Players:GetPlayerFromCharacter(char)
	if player then
		goHome(player)
	end
end)
