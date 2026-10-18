--!strict
--[[
	Paste this Script into ServerScriptService of the Laser Tag PLACE
	(Whiskeandgaming's Place / Laser Tag — not the Brainrot Arena hub).

	Does four jobs:
	1. Orange return gate at every spawn pad (one per spawn room).
	2. Records kills into OrderedDataStore "LaserTagKills_v1" so the plaza
	   board next to the Laser Tag portal can show them.
	3. Opens one-way spawn glass so people in base cannot camp: shots go
	   out AND in.
	4. After 10 seconds in spawn you are pushed into the arena and cannot
	   walk back into spawn.

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
	-- Put the gate to the SIDE of the pad, not in the doorway, so walking out is not a teleport.
	local right = Vector3.new(-flat.Z, 0, flat.X)
	if right.Magnitude < 0.05 then
		right = Vector3.new(1, 0, 0)
	else
		right = right.Unit
	end
	local x = at.X + right.X * 7
	local z = at.Z + right.Z * 7
	local y = at.Y + 3

	local gate = Instance.new("Part")
	gate.Name = "ReturnToArena"
	gate.Size = Vector3.new(4, 8, 0.8)
	gate.Anchored = true
	gate.CanCollide = false
	gate.CanTouch = false
	gate.Color = Color3.fromRGB(255, 180, 40)
	gate.Material = Enum.Material.Neon
	gate.CFrame = CFrame.new(Vector3.new(x, y, z), Vector3.new(x, y, z) + right)
	gate.Parent = workspace

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(0, 220, 0, 48)
	sign.StudsOffset = Vector3.new(0, 8, 0)
	sign.AlwaysOnTop = false
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
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = gate

	prompt.Triggered:Connect(goHome)
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

local fairPassDone = false

local function looksLikeSpawnWindow(part: BasePart): boolean
	if part:IsA("SpawnLocation") or part.Name == "ReturnToArena" then
		return false
	end
	local n = string.lower(part.Name)
	if string.find(n, "window", 1, true)
		or string.find(n, "glass", 1, true)
		or string.find(n, "shield", 1, true)
		or string.find(n, "barrier", 1, true)
		or string.find(n, "protect", 1, true)
		or string.find(n, "forcefield", 1, true)
		or string.find(n, "oneway", 1, true)
	then
		return true
	end
	if part.Material == Enum.Material.ForceField or part.Material == Enum.Material.Glass then
		return true
	end
	if part.Transparency < 0.15 then
		return false
	end
	local size = part.Size
	local thin = math.min(size.X, size.Y, size.Z)
	local long = math.max(size.X, size.Y, size.Z)
	return thin <= 2.5 and long >= 4
end

local function openWindow(part: BasePart)
	part.CanQuery = false
	pcall(function()
		part.CollisionGroup = "Default"
	end)
end

local function makeShotsFair()
	local PhysicsService = game:GetService("PhysicsService")
	local groupNames: { string } = { "Default" }
	pcall(function()
		for _, g in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
			table.insert(groupNames, g.name)
		end
	end)
	for _, a in ipairs(groupNames) do
		for _, b in ipairs(groupNames) do
			pcall(function()
				PhysicsService:CollisionGroupSetCollidable(a, b, true)
			end)
		end
	end

	local opened = 0
	local spawns = collectSpawns()
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("BasePart") and looksLikeSpawnWindow(d) then
			local nearSpawn = #spawns == 0
			if not nearSpawn then
				for _, spawn in ipairs(spawns) do
					local dx = d.Position.X - spawn.Position.X
					local dz = d.Position.Z - spawn.Position.Z
					if math.sqrt(dx * dx + dz * dz) < 70 then
						nearSpawn = true
						break
					end
				end
			end
			if nearSpawn then
				openWindow(d)
				opened += 1
			end
		end
	end

	if not fairPassDone then
		local roots = {
			workspace,
			game:GetService("ServerScriptService"),
			game:GetService("ReplicatedStorage"),
			game:GetService("StarterPlayer"),
			game:GetService("ServerStorage"),
		}
		for _, root in ipairs(roots) do
			for _, d in ipairs(root:GetDescendants()) do
				if d:IsA("BaseScript") then
					local n = string.lower((d.Name :: string))
					n = string.gsub(n, "[^%w]", "")
					if string.find(n, "oneway", 1, true)
						or string.find(n, "spawnprotect", 1, true)
						or string.find(n, "safewindow", 1, true)
						or string.find(n, "teamwindow", 1, true)
						or string.find(n, "spawnshield", 1, true)
						or string.find(n, "spawnbarrier", 1, true)
					then
						d.Disabled = true
						print("[ReturnToArena] disabled " .. d:GetFullName())
					end
				end
			end
		end
	end

	fairPassDone = true
	print("[ReturnToArena] spawn windows opened for two-way shots: " .. tostring(opened))
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

task.defer(function()
	placeAtAllSpawns()
	makeShotsFair()
end)
task.delay(3, function()
	placeAtAllSpawns()
	makeShotsFair()
end)

do
	local GRACE_SECS = 10
	local SPAWN_RADIUS = 40
	local PUSH_STUDS = 48

	local function nearestPad(pos: Vector3): BasePart?
		local best: BasePart? = nil
		local bestD = SPAWN_RADIUS
		for _, spawn in ipairs(collectSpawns()) do
			if spawn:IsDescendantOf(workspace) then
				local dx = pos.X - spawn.Position.X
				local dz = pos.Z - spawn.Position.Z
				local d = math.sqrt(dx * dx + dz * dz)
				if d <= bestD then
					bestD = d
					best = spawn
				end
			end
		end
		return best
	end

	local function ejectToArena(player: Player, pad: BasePart)
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end
		local look = Vector3.new(pad.CFrame.LookVector.X, 0, pad.CFrame.LookVector.Z)
		if look.Magnitude < 0.05 then
			look = Vector3.new(0, 0, -1)
		else
			look = look.Unit
		end
		local dest = pad.Position + look * PUSH_STUDS
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { char }
		local hit = workspace:Raycast(Vector3.new(dest.X, dest.Y + 40, dest.Z), Vector3.new(0, -120, 0), params)
		local y = if hit then hit.Position.Y + 4 else dest.Y + 4
		local destPos = Vector3.new(dest.X, y, dest.Z)
		;(hrp :: BasePart).CFrame = CFrame.lookAt(destPos, destPos + look)
	end

	local function watchSpawn(player: Player, char: Model)
		local born = os.clock()
		while char.Parent and player.Parent do
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				local pad = nearestPad((hrp :: BasePart).Position)
				if pad and os.clock() - born >= GRACE_SECS then
					ejectToArena(player, pad)
				end
			end
			task.wait(0.2)
		end
	end

	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char)
			task.spawn(function()
				watchSpawn(player, char)
			end)
		end)
		if player.Character then
			task.spawn(function()
				watchSpawn(player, player.Character :: Model)
			end)
		end
	end

	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do
		hook(p)
	end
	print("[ReturnToArena] spawn eject after " .. tostring(GRACE_SECS) .. "s")
end
