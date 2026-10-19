--!strict
--[[
	XSFExpandArena — free-for-all PvP layout for the XSF Shooter Arena place.

	Every server start:
	  1. Opens / removes building doors + blocking walls so you can leave
	  2. Deletes training dummies / targets
	  3. Disables the old indoor SpawnLocation
	  4. Builds a fight floor with cover
	  5. Places 5 spread-out FFA spawn pads
	  6. Places 5 orange RETURN TO ARENA portals next to those spawns

	XSFReturn still records kills; it skips building its own gates when this
	script sets Workspace.XSFArenaHandlesReturns = true.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

print("[XSFExpandArena] FFA PvP arena setup...")

local HUB_PLACE_ID = 92909397469421
local PAD = tonumber(workspace:GetAttribute("ArenaPad")) or 32
local RETURN_PLACE_BY_USER: { [number]: number } = {}

local function log(msg: string)
	print("[XSFExpandArena] " .. msg)
end

local function part(
	name: string,
	size: Vector3,
	cf: CFrame,
	color: Color3,
	parent: Instance,
	material: Enum.Material?
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = true
	p.CanCollide = true
	p.Color = color
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function looksLikeDummy(inst: Instance): boolean
	local n = string.lower(inst.Name)
	if string.find(n, "dummy", 1, true)
		or string.find(n, "target", 1, true)
		or string.find(n, "mannequin", 1, true)
		or string.find(n, "training", 1, true)
		or n == "npc"
	then
		return true
	end
	if inst:IsA("Model") then
		local hum = inst:FindFirstChildOfClass("Humanoid")
		if hum and not Players:GetPlayerFromCharacter(inst) then
			return true
		end
	end
	return false
end

local function looksLikeDoor(partInst: BasePart): boolean
	local n = string.lower(partInst.Name)
	if string.find(n, "door", 1, true)
		or string.find(n, "gate", 1, true)
		or string.find(n, "entrance", 1, true)
		or string.find(n, "exit", 1, true)
	then
		return true
	end
	-- Thin tall slabs are often doors / wall panels
	local size = partInst.Size
	local thin = math.min(size.X, size.Z)
	return thin <= 1.5 and size.Y >= 5 and math.max(size.X, size.Z) >= 3 and math.max(size.X, size.Z) <= 12
end

local function worldPos(inst: Instance): Vector3?
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local ok, cf = pcall(function()
			return (inst :: Model):GetPivot()
		end)
		if ok and cf then
			return cf.Position
		end
		local pp = (inst :: Model).PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		if pp and pp:IsA("BasePart") then
			return pp.Position
		end
	end
	return nil
end

local function collectSpawns(): { BasePart }
	local out: { BasePart } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			table.insert(out, d)
		end
	end
	return out
end

local function collectDummies(): { Instance }
	local out: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if looksLikeDummy(d) then
			local root: Instance = d
			if d:IsA("BasePart") and d.Parent and looksLikeDummy(d.Parent) then
				root = d.Parent
			end
			if not seen[root] then
				seen[root] = true
				table.insert(out, root)
			end
		end
	end
	return out
end

local function boundsFromPoints(points: { Vector3 }): (Vector3, Vector3)?
	if #points == 0 then
		return nil
	end
	local minV = points[1]
	local maxV = points[1]
	for i = 2, #points do
		local p = points[i]
		minV = Vector3.new(math.min(minV.X, p.X), math.min(minV.Y, p.Y), math.min(minV.Z, p.Z))
		maxV = Vector3.new(math.max(maxV.X, p.X), math.max(maxV.Y, p.Y), math.max(maxV.Z, p.Z))
	end
	return minV, maxV
end

-- Remove doors + open wall panels around the starter building (all sides).
local function openBuilding(spawnPos: Vector3)
	local removed = 0
	local opened = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if not d:IsA("BasePart") or not d.Anchored then
			continue
		end
		if d:IsA("SpawnLocation") or d.Name == "Baseplate" or d.Name == "Terrain" then
			continue
		end
		if string.find(d.Name, "XSFArena", 1, true) or string.find(d.Name, "ReturnToArena", 1, true) then
			continue
		end
		local expand = workspace:FindFirstChild("XSFArenaExpand")
		if expand and d:IsDescendantOf(expand) then
			continue
		end

		local flat = Vector3.new(d.Position.X - spawnPos.X, 0, d.Position.Z - spawnPos.Z)
		if flat.Magnitude > 60 then
			continue
		end

		if looksLikeDoor(d) then
			d:Destroy()
			removed += 1
			continue
		end

		-- Perimeter walls of the courtyard / building: thin + tall near spawn
		local size = d.Size
		local thin = math.min(size.X, size.Y, size.Z)
		if d.CanCollide and thin <= 2.5 and size.Y >= 4 and flat.Magnitude >= 4 and flat.Magnitude <= 50 then
			d.CanCollide = false
			d.Transparency = math.max(d.Transparency, 0.9)
			d.Name = d.Name .. "_OpenedExit"
			opened += 1
		end
	end
	log("removed doors=" .. tostring(removed) .. " opened wall panels=" .. tostring(opened))
end

local function removeDummies(dummies: { Instance })
	for _, d in ipairs(dummies) do
		d:Destroy()
	end
	log("removed training dummies/targets: " .. tostring(#dummies))
end

local function disableOldSpawns(spawns: { BasePart }, folder: Folder)
	for _, s in ipairs(spawns) do
		if s.Parent and not s:IsDescendantOf(folder) then
			s.Enabled = false
			s.Transparency = 1
			s.CanCollide = false
			s.Name = s.Name .. "_DisabledOld"
		end
	end
	log("disabled old indoor spawn pads: " .. tostring(#spawns))
end

local function hubIdFor(player: Player): number
	return RETURN_PLACE_BY_USER[player.UserId] or HUB_PLACE_ID
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

Players.PlayerAdded:Connect(function(player)
	local join = player:GetJoinData()
	local data = join and join.TeleportData
	if type(data) == "table" and type(data.ReturnPlaceId) == "number" and data.ReturnPlaceId > 0 then
		RETURN_PLACE_BY_USER[player.UserId] = data.ReturnPlaceId
	end
end)
Players.PlayerRemoving:Connect(function(player)
	RETURN_PLACE_BY_USER[player.UserId] = nil
end)

local function placeReturnPortal(parent: Instance, at: Vector3, index: number)
	local gate = Instance.new("Part")
	gate.Name = "ReturnToArena_" .. tostring(index)
	gate.Size = Vector3.new(5, 10, 1)
	gate.Anchored = true
	gate.CanCollide = false
	gate.CanTouch = false
	gate.Color = Color3.fromRGB(255, 140, 40)
	gate.Material = Enum.Material.Neon
	gate.CFrame = CFrame.new(at + Vector3.new(0, 5, 0))
	gate.Parent = parent

	local light = Instance.new("PointLight")
	light.Brightness = 2
	light.Range = 16
	light.Color = Color3.fromRGB(255, 160, 50)
	light.Parent = gate

	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.new(0, 240, 0, 56)
	sign.StudsOffset = Vector3.new(0, 7, 0)
	sign.AlwaysOnTop = true
	sign.Parent = gate
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 220, 100)
	label.TextStrokeTransparency = 0.25
	label.Text = "RETURN TO ARENA"
	label.Parent = sign

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Return"
	prompt.ObjectText = "Brainrot Arena"
	prompt.HoldDuration = 0.35
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = gate
	prompt.Triggered:Connect(goHome)
end

local function buildArena(minV: Vector3, maxV: Vector3, floorY: number): Folder
	local old = workspace:FindFirstChild("XSFArenaExpand")
	if old then
		old:Destroy()
	end

	local folder = Instance.new("Folder")
	folder.Name = "XSFArenaExpand"
	folder.Parent = workspace

	local minX, maxX = minV.X - PAD, maxV.X + PAD
	local minZ, maxZ = minV.Z - PAD, maxV.Z + PAD
	local width = math.max(maxX - minX, 100)
	local depth = math.max(maxZ - minZ, 100)
	local cx = (minX + maxX) * 0.5
	local cz = (minZ + maxZ) * 0.5
	minX, maxX = cx - width * 0.5, cx + width * 0.5
	minZ, maxZ = cz - depth * 0.5, cz + depth * 0.5

	local floorThickness = 2
	local wallH = 12
	local wallT = 2
	local y = floorY
	local wallColor = Color3.fromRGB(55, 58, 64)

	part(
		"FightFloor",
		Vector3.new(width, floorThickness, depth),
		CFrame.new(cx, y - floorThickness * 0.5, cz),
		Color3.fromRGB(70, 72, 78),
		folder,
		Enum.Material.Concrete
	)

	-- Outer walls with wide gaps on all four sides (open arena feel)
	local gap = 18
	local function splitWall(name: string, alongX: boolean, edge: number)
		local long = if alongX then width else depth
		local seg = (long - gap) * 0.5
		if alongX then
			part(name .. "L", Vector3.new(seg, wallH, wallT), CFrame.new(cx - gap * 0.5 - seg * 0.5, y + wallH * 0.5, edge), wallColor, folder)
			part(name .. "R", Vector3.new(seg, wallH, wallT), CFrame.new(cx + gap * 0.5 + seg * 0.5, y + wallH * 0.5, edge), wallColor, folder)
		else
			part(name .. "L", Vector3.new(wallT, wallH, seg), CFrame.new(edge, y + wallH * 0.5, cz - gap * 0.5 - seg * 0.5), wallColor, folder)
			part(name .. "R", Vector3.new(wallT, wallH, seg), CFrame.new(edge, y + wallH * 0.5, cz + gap * 0.5 + seg * 0.5), wallColor, folder)
		end
	end
	splitWall("WallN", true, minZ - wallT * 0.5)
	splitWall("WallS", true, maxZ + wallT * 0.5)
	splitWall("WallW", false, minX - wallT * 0.5)
	splitWall("WallE", false, maxX + wallT * 0.5)

	-- Cover for FFA fights
	local coverColor = Color3.fromRGB(90, 70, 50)
	local rng = Random.new(42)
	for i = 1, 12 do
		local x = cx + rng:NextNumber(-width * 0.32, width * 0.32)
		local z = cz + rng:NextNumber(-depth * 0.32, depth * 0.32)
		local w = rng:NextNumber(4, 9)
		local h = rng:NextNumber(3, 6)
		local dpth = rng:NextNumber(3, 7)
		part("Cover" .. tostring(i), Vector3.new(w, h, dpth), CFrame.new(x, y + h * 0.5, z), coverColor, folder, Enum.Material.Wood)
	end

	-- 5 FFA spawns: 4 corners + mid-edge (not center — less spawn camping)
	local pads = {
		Vector3.new(minX + 12, y + 1, minZ + 12),
		Vector3.new(maxX - 12, y + 1, minZ + 12),
		Vector3.new(minX + 12, y + 1, maxZ - 12),
		Vector3.new(maxX - 12, y + 1, maxZ - 12),
		Vector3.new(cx, y + 1, minZ + 12),
	}
	for i, pos in ipairs(pads) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "FFASpawn_" .. tostring(i)
		spawn.Size = Vector3.new(8, 1, 8)
		spawn.Anchored = true
		spawn.CanCollide = true
		spawn.Enabled = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.AllowTeamChangeOnTouch = false
		spawn.Color = Color3.fromRGB(40, 140, 220)
		spawn.Material = Enum.Material.Neon
		spawn.CFrame = CFrame.new(pos)
		spawn.Parent = folder

		-- Return portal just beside each spawn (offset inward so it isn't on the pad)
		local inward = Vector3.new(cx - pos.X, 0, cz - pos.Z)
		if inward.Magnitude < 1 then
			inward = Vector3.new(0, 0, 8)
		else
			inward = inward.Unit * 10
		end
		placeReturnPortal(folder, pos + inward, i)
	end

	log(string.format("FFA floor %.0fx%.0f | 5 spawns | 5 return portals", width, depth))
	return folder
end

local function run()
	workspace:SetAttribute("XSFArenaHandlesReturns", true)

	local spawns = collectSpawns()
	local dummies = collectDummies()
	log("old spawns=" .. tostring(#spawns) .. " dummies=" .. tostring(#dummies))

	local points: { Vector3 } = {}
	for _, s in ipairs(spawns) do
		table.insert(points, s.Position)
	end
	for _, d in ipairs(dummies) do
		local p = worldPos(d)
		if p then
			table.insert(points, p)
		end
	end
	if #spawns > 0 then
		local origin = spawns[1].Position
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.Anchored and d.CanCollide then
				local flat = Vector3.new(d.Position.X - origin.X, 0, d.Position.Z - origin.Z)
				if flat.Magnitude < 80 then
					table.insert(points, d.Position)
				end
			end
		end
	end

	local minV, maxV = boundsFromPoints(points)
	if not minV or not maxV then
		minV = Vector3.new(-50, 0, -50)
		maxV = Vector3.new(50, 0, 50)
		warn("[XSFExpandArena] no landmarks — default 100x100 arena")
	end

	local floorY = if #spawns > 0 then spawns[1].Position.Y - 0.5 else minV.Y
	local spawnPos = if #spawns > 0 then spawns[1].Position else Vector3.new(0, floorY, 0)

	removeDummies(dummies)
	openBuilding(spawnPos)
	local folder = buildArena(minV, maxV, floorY)
	disableOldSpawns(spawns, folder)

	local floor = folder:FindFirstChild("FightFloor")
	local cx, cz = 0, 0
	if floor and floor:IsA("BasePart") then
		cx = floor.Position.X
		cz = floor.Position.Z
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			hrp.CFrame = CFrame.new(cx, floorY + 5, cz)
		end
	end

	log("done — FFA PvP ready (5 spawns + 5 return portals)")
end

task.defer(run)
