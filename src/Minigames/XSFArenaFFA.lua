--[[
	XSFArenaFFA — free-for-all PvP layout for the XSF Shooter Arena place.

	Every server start:
	  1. Deletes training dummies / targets ONLY
	  2. Does NOT touch the building (walls/doors) — edit those in Studio yourself
	  3. Disables the old indoor SpawnLocation
	  4. Builds a fight floor with cover
	  5. Places 5 spread-out FFA spawn pads
	  6. Places 5 orange RETURN TO ARENA portals next to those spawns

	XSFReturn still records kills; it skips building its own gates when this
	script sets Workspace.XSFArenaHandlesReturns = true.
]]

local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")

print("[XSFArenaFFA] FFA PvP arena setup...")

local HUB_PLACE_ID = 92909397469421
local PAD = tonumber(workspace:GetAttribute("ArenaPad")) or 32
local RETURN_PLACE_BY_USER = {}

local function log(msg)
	print("[XSFArenaFFA] " .. msg)
end

local function part(name, size, cf, color, parent, material)
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

local function looksLikeDummy(inst)
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

local function worldPos(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	end
	if inst:IsA("Model") then
		local ok, cf = pcall(function()
			return inst:GetPivot()
		end)
		if ok and cf then
			return cf.Position
		end
		local pp = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		if pp and pp:IsA("BasePart") then
			return pp.Position
		end
	end
	return nil
end

local function collectSpawns()
	local out = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if d:IsA("SpawnLocation") then
			table.insert(out, d)
		end
	end
	return out
end

local function collectDummies()
	local out = {}
	local seen = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if looksLikeDummy(d) then
			local root = d
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

local function boundsFromPoints(points)
	if #points == 0 then
		return nil, nil
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

-- Building is hands-off. Owner deletes the door in Studio if needed.
local function openBuilding(_spawnPos)
	log("building left untouched (dummies only; edit doors in Studio yourself)")
end

local function removeDummies(dummies)
	for _, d in ipairs(dummies) do
		d:Destroy()
	end
	log("removed training dummies/targets: " .. tostring(#dummies))
end

local function disableOldSpawns(spawns, folder)
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

local function hubIdFor(player)
	return RETURN_PLACE_BY_USER[player.UserId] or HUB_PLACE_ID
end

local function goHome(player)
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

local function placeReturnPortal(parent, at, index)
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

-- Hide every flat ground surface under the arena so only FightFloor draws.
-- (Two coplanar floors = the bad flicker / z-fighting.)
local function neutralizeOldGround(floorY, minX, maxX, minZ, maxZ, keepFolder)
	local n = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		local skip = false
		if not (d:IsA("BasePart") and d.Anchored) then
			skip = true
		elseif d:IsA("SpawnLocation") then
			skip = true
		elseif keepFolder and d:IsDescendantOf(keepFolder) then
			skip = true
		end
		if not skip then
			local size = d.Size
			local topY = d.Position.Y + size.Y * 0.5
			local halfX = size.X * 0.5
			local halfZ = size.Z * 0.5
			local overlaps = (d.Position.X - halfX) < maxX
				and (d.Position.X + halfX) > minX
				and (d.Position.Z - halfZ) < maxZ
				and (d.Position.Z + halfZ) > minZ
			local flat = size.Y <= 5
			local near = topY >= floorY - 3 and topY <= floorY + 4
			if flat and near and overlaps then
				d.Transparency = 1
				d.CanCollide = false
				d.CanQuery = false
				d.CanTouch = false
				d.CastShadow = false
				n = n + 1
			end
		end
	end
	-- Clear terrain voxels in the fight volume so Terrain can't z-fight either.
	pcall(function()
		local terrain = workspace.Terrain
		local r = Region3.new(
			Vector3.new(minX, floorY - 8, minZ),
			Vector3.new(maxX, floorY + 2, maxZ)
		)
		r = r:ExpandToGrid(4)
		terrain:FillRegion(r, 4, Enum.Material.Air)
	end)
	log("neutralized old ground parts: " .. tostring(n))
end

local function buildArena(minV, maxV, floorY)
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

	-- One walkable slab only. Old floors are hidden first (see above).
	local SURFACE_LIFT = 0.5
	local floorThickness = 3
	local wallH = 12
	local wallT = 2
	local y = floorY + SURFACE_LIFT
	local wallColor = Color3.fromRGB(55, 58, 64)

	neutralizeOldGround(floorY, minX, maxX, minZ, maxZ, folder)

	local fightFloor = part(
		"FightFloor",
		Vector3.new(width, floorThickness, depth),
		CFrame.new(cx, y - floorThickness * 0.5, cz),
		Color3.fromRGB(70, 72, 78),
		folder,
		Enum.Material.Concrete
	)
	fightFloor.CastShadow = false

	local gap = 18
	local function splitWall(name, alongX, edge)
		local long
		if alongX then
			long = width
		else
			long = depth
		end
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
	-- Let XSFUnpack finish moving XSF_TestMap out of the package first.
	task.wait(1)
	workspace:SetAttribute("XSFArenaHandlesReturns", true)

	local spawns = collectSpawns()
	local dummies = collectDummies()
	log("old spawns=" .. tostring(#spawns) .. " dummies=" .. tostring(#dummies))

	local points = {}
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
		warn("[XSFArenaFFA] no landmarks — default 100x100 arena")
	end

	local floorY = minV.Y
	local spawnPos = Vector3.new(0, floorY, 0)
	if #spawns > 0 then
		floorY = spawns[1].Position.Y - 0.5
		spawnPos = spawns[1].Position
	end

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
