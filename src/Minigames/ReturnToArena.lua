--!strict
--[[
	Paste this Script into ServerScriptService of the Laser Tag PLACE
	(Whiskeandgaming's Place / Laser Tag — not the Brainrot Arena hub).

	Does two jobs:
	1. Orange return gate at every spawn pad (one per spawn room).
	2. Records kills into OrderedDataStore "LaserTagKills_v1" so the plaza
	   board next to the Laser Tag portal can show them.

	After pasting: File → Publish to Roblox → overwrite THIS laser tag place only.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local DataStoreService = game:GetService("DataStoreService")

print("[ReturnToArena] script running in " .. tostring(script:GetFullName()))

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

local function goHome(player: Player)
	local placeId = hubIdFor(player)
	if placeId <= 0 then
		return
	end
	pcall(function()
		TeleportService:TeleportAsync(placeId, { player })
	end)
end

local placedCenters: { Vector3 } = {}

local function tooClose(pos: Vector3): boolean
	for _, other in ipairs(placedCenters) do
		if (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(other.X, 0, other.Z)).Magnitude < 16 then
			return true
		end
	end
	return false
end

local function groundAt(x: number, yHint: number, z: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = {}
	local hit = workspace:Raycast(Vector3.new(x, yHint + 40, z), Vector3.new(0, -120, 0), params)
	if hit then
		return hit.Position.Y
	end
	return yHint
end

local function placeReturnGate(at: Vector3, look: Vector3?)
	if tooClose(at) then
		return
	end
	table.insert(placedCenters, at)
	local flat = look and Vector3.new(look.X, 0, look.Z) or Vector3.new(0, 0, -1)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	local x = at.X + flat.X * 8
	local z = at.Z + flat.Z * 8
	local y = groundAt(x, at.Y, z) + 6

	local gate = Instance.new("Part")
	gate.Name = "ReturnToArena"
	gate.Size = Vector3.new(8, 14, 1.6)
	gate.Anchored = true
	gate.CanCollide = false
	gate.Color = Color3.fromRGB(255, 180, 40)
	gate.Material = Enum.Material.Neon
	gate.CFrame = CFrame.new(Vector3.new(x, y, z), Vector3.new(x, y, z) + flat)
	gate.Parent = workspace

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(0, 220, 0, 48)
	sign.StudsOffset = Vector3.new(0, 7, 0)
	sign.AlwaysOnTop = true
	sign.Parent = gate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 220, 80)
	label.TextStrokeTransparency = 0.3
	label.Text = "RETURN TO ARENA"
	label.Parent = sign

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Return"
	prompt.ObjectText = "Brainrot Arena"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 18
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = gate

	prompt.Triggered:Connect(goHome)
	gate.Touched:Connect(function(hit: BasePart)
		local char = hit and hit.Parent
		local player = char and Players:GetPlayerFromCharacter(char)
		if player then
			goHome(player)
		end
	end)
end

local function collectSpawns(): { BasePart }
	local found: { BasePart } = {}
	local roots = { workspace, game:GetService("ServerStorage"), game:GetService("ReplicatedStorage") }
	for _, root in ipairs(roots) do
		for _, d in ipairs(root:GetDescendants()) do
			if d:IsA("SpawnLocation") then
				table.insert(found, d)
			end
		end
	end
	return found
end

local function placeAtAllSpawns()
	local spawns = collectSpawns()
	print("[ReturnToArena] spawn pads found: " .. tostring(#spawns))
	if #spawns == 0 then
		placeReturnGate(Vector3.new(0, 20, 0), Vector3.new(0, 0, -1))
		return
	end
	for _, spawn in ipairs(spawns) do
		placeReturnGate(spawn.Position, spawn.CFrame.LookVector)
	end
end

local function placeBesidePlayer(player: Player)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) then
		return
	end
	local look = (hrp :: BasePart).CFrame.LookVector
	placeReturnGate((hrp :: BasePart).Position + look * 10, look)
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(function()
		task.wait(1.2)
		placeBesidePlayer(player)
	end)
end)
for _, player in ipairs(Players:GetPlayers()) do
	player.CharacterAdded:Connect(function()
		task.wait(1.2)
		placeBesidePlayer(player)
	end)
	if player.Character then
		task.defer(function()
			placeBesidePlayer(player)
		end)
	end
end

task.defer(placeAtAllSpawns)
task.delay(3, placeAtAllSpawns)
