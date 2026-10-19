--!strict
--[[
	XSFExpandArena — paste into ServerScriptService of the XSF Shooter Arena place.

	Fixes the "stuck in the starter building" problem and expands a fight floor
	across the training-dummy / target range so players have room for PvP.

	Every server start it:
	  1. Finds spawn pads + training dummies/targets
	  2. Opens doorway holes in walls between spawn and the range
	  3. Builds a big ArenaExpand floor + outer walls + cover
	  4. Adds extra spawn pads around the fight zone
	  5. Parks dummies at the edges (keeps them as props, out of mid-fight)

	Safe to re-run (destroys previous Workspace.XSFArenaExpand first).
	Tuning (optional Workspace attributes):
	  ArenaPad = 24     -- studs of padding past dummies
	  ArenaKeepDummies = true/false  -- false = delete dummies
]]

local Players = game:GetService("Players")

print("[XSFExpandArena] building PvP arena...")

local PAD = tonumber(workspace:GetAttribute("ArenaPad")) or 28
local KEEP_DUMMIES = workspace:GetAttribute("ArenaKeepDummies")
if KEEP_DUMMIES == nil then
	KEEP_DUMMIES = true
end

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
		or string.find(n, "npc", 1, true)
	then
		return true
	end
	if inst:IsA("Model") then
		local hum = inst:FindFirstChildOfClass("Humanoid")
		if hum and not Players:GetPlayerFromCharacter(inst) then
			-- Non-player humanoid = likely a range dummy
			return true
		end
	end
	return false
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
		if d:IsA("SpawnLocation") and d:IsDescendantOf(workspace) then
			table.insert(out, d)
		end
	end
	return out
end

local function collectDummies(): { Instance }
	local out: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	for _, d in ipairs(workspace:GetDescendants()) do
		if looksLikeDummy(d) and not seen[d] then
			-- Prefer the model root over every child part
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

-- Open thin walls between spawn and the fight area so players can walk out.
local function openExits(spawnPos: Vector3, toward: Vector3)
	local dir = toward - spawnPos
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 1 then
		dir = Vector3.new(0, 0, -1)
	else
		dir = dir.Unit
	end

	local opened = 0
	for _, d in ipairs(workspace:GetDescendants()) do
		if not d:IsA("BasePart") or not d.CanCollide or d.Anchored == false then
			continue
		end
		if d:IsA("SpawnLocation") or d.Name == "Terrain" then
			continue
		end
		local expand = workspace:FindFirstChild("XSFArenaExpand")
		if expand and d:IsDescendantOf(expand) then
			continue
		end
		if string.find(d.Name, "XSFArena", 1, true) or string.find(d.Name, "_OpenedExit", 1, true) then
			continue
		end

		local size = d.Size
		local thin = math.min(size.X, size.Y, size.Z)
		local tall = size.Y
		if thin > 2.8 or tall < 4 then
			continue
		end

		local toPart = d.Position - spawnPos
		local flat = Vector3.new(toPart.X, 0, toPart.Z)
		if flat.Magnitude > 55 or flat.Magnitude < 2 then
			continue
		end
		-- Roughly in the direction of the range
		if flat.Unit:Dot(dir) < 0.35 then
			continue
		end

		-- Cut a doorway: turn into non-collide + fade, or punch a hole part
		d.CanCollide = false
		d.Transparency = math.max(d.Transparency, 0.85)
		d.Name = d.Name .. "_OpenedExit"
		opened += 1
		if opened >= 14 then
			break
		end
	end
	log("opened exit panels near spawn: " .. tostring(opened))
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
	-- Enforce a usable fight size even if dummies were clustered
	local width = math.max(maxX - minX, 90)
	local depth = math.max(maxZ - minZ, 90)
	local cx = (minX + maxX) * 0.5
	local cz = (minZ + maxZ) * 0.5
	minX, maxX = cx - width * 0.5, cx + width * 0.5
	minZ, maxZ = cz - depth * 0.5, cz + depth * 0.5

	local floorThickness = 2
	local wallH = 14
	local wallT = 2
	local y = floorY

	part(
		"FightFloor",
		Vector3.new(width, floorThickness, depth),
		CFrame.new(cx, y - floorThickness * 0.5, cz),
		Color3.fromRGB(70, 72, 78),
		folder,
		Enum.Material.Concrete
	)

	-- Outer walls
	local wallColor = Color3.fromRGB(55, 58, 64)
	part("WallN", Vector3.new(width + wallT * 2, wallH, wallT), CFrame.new(cx, y + wallH * 0.5, minZ - wallT * 0.5), wallColor, folder)
	part("WallS", Vector3.new(width + wallT * 2, wallH, wallT), CFrame.new(cx, y + wallH * 0.5, maxZ + wallT * 0.5), wallColor, folder)
	part("WallW", Vector3.new(wallT, wallH, depth), CFrame.new(minX - wallT * 0.5, y + wallH * 0.5, cz), wallColor, folder)
	part("WallE", Vector3.new(wallT, wallH, depth), CFrame.new(maxX + wallT * 0.5, y + wallH * 0.5, cz), wallColor, folder)

	-- Door gaps in N/S walls (openings for flow)
	for _, zSide in ipairs({ minZ, maxZ }) do
		local door = part(
			"DoorGapMarker",
			Vector3.new(12, 8, wallT + 0.4),
			CFrame.new(cx, y + 4, zSide + (if zSide == minZ then -wallT * 0.5 else wallT * 0.5)),
			Color3.fromRGB(30, 30, 30),
			folder,
			Enum.Material.Neon
		)
		door.CanCollide = false
		door.Transparency = 0.7
	end
	-- Actually cut collide holes by shortening walls conceptually: add non-collide overlays only.
	-- Punch real gaps: destroy center of N/S walls and replace with two segments.
	for _, wallName in ipairs({ "WallN", "WallS" }) do
		local wall = folder:FindFirstChild(wallName)
		if wall and wall:IsA("BasePart") then
			local z = wall.Position.Z
			local yMid = wall.Position.Y
			wall:Destroy()
			local gap = 14
			local seg = (width - gap) * 0.5
			part(wallName .. "L", Vector3.new(seg, wallH, wallT), CFrame.new(cx - gap * 0.5 - seg * 0.5, yMid, z), wallColor, folder)
			part(wallName .. "R", Vector3.new(seg, wallH, wallT), CFrame.new(cx + gap * 0.5 + seg * 0.5, yMid, z), wallColor, folder)
		end
	end

	-- Cover props for fights
	local coverColor = Color3.fromRGB(90, 70, 50)
	local rng = Random.new(42)
	for i = 1, 10 do
		local x = cx + rng:NextNumber(-width * 0.35, width * 0.35)
		local z = cz + rng:NextNumber(-depth * 0.35, depth * 0.35)
		local w = rng:NextNumber(4, 9)
		local h = rng:NextNumber(3, 6)
		local d = rng:NextNumber(3, 7)
		part("Cover" .. tostring(i), Vector3.new(w, h, d), CFrame.new(x, y + h * 0.5, z), coverColor, folder, Enum.Material.Wood)
	end

	-- Extra spawn pads around the floor (fair PvP)
	local pads = {
		Vector3.new(minX + 10, y + 1, minZ + 10),
		Vector3.new(maxX - 10, y + 1, minZ + 10),
		Vector3.new(minX + 10, y + 1, maxZ - 10),
		Vector3.new(maxX - 10, y + 1, maxZ - 10),
		Vector3.new(cx, y + 1, cz),
	}
	for i, pos in ipairs(pads) do
		local spawn = Instance.new("SpawnLocation")
		spawn.Name = "ArenaSpawn_" .. tostring(i)
		spawn.Size = Vector3.new(6, 1, 6)
		spawn.Anchored = true
		spawn.CanCollide = true
		spawn.Neutral = true
		spawn.Duration = 0
		spawn.Color = Color3.fromRGB(40, 120, 200)
		spawn.Material = Enum.Material.Neon
		spawn.CFrame = CFrame.new(pos)
		spawn.Parent = folder
	end

	log(string.format("fight floor %.0fx%.0f studs at (%.0f, %.0f, %.0f)", width, depth, cx, y, cz))
	return folder
end

local function relocateDummies(dummies: { Instance }, minX: number, maxX: number, minZ: number, maxZ: number, floorY: number)
	if not KEEP_DUMMIES then
		for _, d in ipairs(dummies) do
			d:Destroy()
		end
		log("removed " .. tostring(#dummies) .. " dummies")
		return
	end
	-- Park them along the inner edge so mid-floor is clear for players
	local edge = {
		Vector3.new(minX + 6, floorY + 3, (minZ + maxZ) * 0.5),
		Vector3.new(maxX - 6, floorY + 3, (minZ + maxZ) * 0.5),
		Vector3.new((minX + maxX) * 0.5, floorY + 3, minZ + 6),
		Vector3.new((minX + maxX) * 0.5, floorY + 3, maxZ - 6),
	}
	for i, d in ipairs(dummies) do
		local dest = edge[((i - 1) % #edge) + 1]
		if d:IsA("Model") then
			pcall(function()
				(d :: Model):PivotTo(CFrame.new(dest))
			end)
		elseif d:IsA("BasePart") then
			d.CFrame = CFrame.new(dest)
		end
	end
	log("parked " .. tostring(#dummies) .. " dummies along arena edges")
end

local function run()
	local spawns = collectSpawns()
	local dummies = collectDummies()
	log("spawns=" .. tostring(#spawns) .. " dummies/targets=" .. tostring(#dummies))

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

	-- Also include nearby building parts around first spawn so the floor covers the house
	if #spawns > 0 then
		local origin = spawns[1].Position
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("BasePart") and d.Anchored and d.CanCollide then
				local flat = Vector3.new(d.Position.X - origin.X, 0, d.Position.Z - origin.Z)
				if flat.Magnitude < 70 then
					table.insert(points, d.Position)
				end
			end
		end
	end

	local minV, maxV = boundsFromPoints(points)
	if not minV or not maxV then
		-- Fallback: expand around world origin / baseplate
		minV = Vector3.new(-40, 0, -40)
		maxV = Vector3.new(40, 0, 40)
		warn("[XSFExpandArena] no spawns/dummies found — building default 80x80 arena at origin")
	end

	local floorY = minV.Y
	if #spawns > 0 then
		floorY = spawns[1].Position.Y - 0.5
	end

	local spawnPos = if #spawns > 0 then spawns[1].Position else Vector3.new(0, floorY, 0)
	local toward = Vector3.new((minV.X + maxV.X) * 0.5, floorY, (minV.Z + maxV.Z) * 0.5)
	-- Prefer direction toward dummies if any
	if #dummies > 0 then
		local dp = worldPos(dummies[1])
		if dp then
			toward = dp
		end
	end

	openExits(spawnPos, toward)
	local folder = buildArena(minV, maxV, floorY)

	local floor = folder:FindFirstChild("FightFloor")
	local halfW, halfD = 45, 45
	if floor and floor:IsA("BasePart") then
		halfW = floor.Size.X * 0.5
		halfD = floor.Size.Z * 0.5
	end
	local cx = (minV.X + maxV.X) * 0.5
	local cz = (minV.Z + maxV.Z) * 0.5
	relocateDummies(dummies, cx - halfW, cx + halfW, cz - halfD, cz + halfD, floorY)

	-- Nudge anyone currently stuck inside the old room onto the new floor
	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			local p = hrp.Position
			if (p - spawnPos).Magnitude < 25 then
				hrp.CFrame = CFrame.new(cx, floorY + 4, cz)
			end
		end
	end

	log("done — walk out the opened walls onto the fight floor")
end

task.defer(run)
