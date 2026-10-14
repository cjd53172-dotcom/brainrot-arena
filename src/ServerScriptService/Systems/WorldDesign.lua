--!strict
--[[
	WorldDesign (ModuleScript -> ServerScriptService/Systems)
	Beauty pass: central plaza, pathways, landscaping, ambient life, lighting.
	Makes the world feel like a cohesive, beautiful place instead of
	scattered game objects on terrain.
	All placement uses terrain raycasting to sit naturally on the map.
]]

local WorldDesign = {}

local CENTER_X = 127
local CENTER_Z = 98

-- Raycast to terrain for grounding.
local function groundY(x: number, z: number): number
	local result: number? = nil
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(
			Vector3.new(x, 500, z),
			Vector3.new(0, -1000, 0),
			params
		)
		if r then
			result = r.Position.Y
		end
	end)
	return result or 16
end

-- Helper: create a part.
local function part(
	size: Vector3,
	pos: Vector3,
	color: Color3,
	material: Enum.Material?,
	parent: Instance?
): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Position = pos
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	if parent then p.Parent = parent end
	return p
end

-- // Central Plaza ------------------------------------------------------------------
function WorldDesign.BuildPlaza(): Model
	local model = Instance.new("Model")
	model.Name = "CentralPlaza"
	local cx, cz = CENTER_X, CENTER_Z
	local gy = groundY(cx, cz)

	-- Circular stone plaza (layered discs)
	for i, r in ipairs({ 18, 14, 10 }) do
		local disc = part(
			Vector3.new(r * 2, 1, r * 2),
			Vector3.new(cx, gy + 0.5 + (3 - i) * 0.3, cz),
			if i == 1 then Color3.fromRGB(120, 120, 130)
			elseif i == 2 then Color3.fromRGB(140, 140, 150)
			else Color3.fromRGB(160, 160, 170),
			Enum.Material.Cobblestone,
			model
		)
		disc.Shape = Enum.PartType.Cylinder
	end

	-- Center fountain
	local fountainBase = part(
		Vector3.new(8, 2, 8),
		Vector3.new(cx, gy + 2, cz),
		Color3.fromRGB(130, 130, 145),
		Enum.Material.Marble,
		model
	)
	fountainBase.Shape = Enum.PartType.Cylinder

	local fountainTop = part(
		Vector3.new(5, 1, 5),
		Vector3.new(cx, gy + 3.5, cz),
		Color3.fromRGB(150, 150, 165),
		Enum.Material.Marble,
		model
	)
	fountainTop.Shape = Enum.PartType.Cylinder

	-- Water in fountain
	local water = part(
		Vector3.new(7, 0.5, 7),
		Vector3.new(cx, gy + 3, cz),
		Color3.fromRGB(80, 160, 220),
		Enum.Material.Water,
		model
	)
	water.Shape = Enum.PartType.Cylinder
	water.Transparency = 0.2

	-- Center spire
	part(
		Vector3.new(1.5, 5, 1.5),
		Vector3.new(cx, gy + 5, cz),
		Color3.fromRGB(140, 140, 155),
		Enum.Material.Marble,
		model
	)

	-- Water spray particles
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(150, 200, 255))
	spray.Size = NumberSequence.new(0.8)
	spray.Speed = NumberRange.new(8, 12)
	spray.Lifetime = NumberRange.new(1, 1.5)
	spray.Rate = 30
	spray.EmissionDirection = Enum.NormalId.Top
	spray.Parent = water

	-- Sparkle light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(150, 200, 255)
	light.Range = 20
	light.Brightness = 1
	light.Parent = water

	-- Benches around plaza (4)
	for i = 0, 3 do
		local angle = math.rad(i * 90 + 45)
		local bx = cx + math.cos(angle) * 13
		local bz = cz + math.sin(angle) * 13
		local bgy = groundY(bx, bz)
		-- Seat
		part(
			Vector3.new(4, 0.5, 1.5),
			Vector3.new(bx, bgy + 1.5, bz),
			Color3.fromRGB(110, 75, 40),
			Enum.Material.Wood,
			model
		)
		-- Legs
		for _, dx in ipairs({ -1.5, 1.5 }) do
			part(
				Vector3.new(0.4, 1.5, 1.2),
				Vector3.new(bx + dx, bgy + 0.75, bz),
				Color3.fromRGB(80, 55, 30),
				Enum.Material.Wood,
				model
			)
		end
	end

	-- Lamp posts around plaza (4)
	for i = 0, 3 do
		local angle = math.rad(i * 90)
		local lx = cx + math.cos(angle) * 16
		local lz = cz + math.sin(angle) * 16
		local lgy = groundY(lx, lz)
		WorldDesign.BuildLamp(lx, lgy, lz, model)
	end

	model.Parent = workspace
	return model
end

-- Decorative lamp post.
function WorldDesign.BuildLamp(x: number, gy: number, z: number, parent: Instance?)
	local model = Instance.new("Model")
	model.Name = "LampPost"

	part(
		Vector3.new(0.5, 5, 0.5),
		Vector3.new(x, gy + 2.5, z),
		Color3.fromRGB(50, 50, 60),
		Enum.Material.Metal,
		model
	)
	local lampHead = part(
		Vector3.new(1.2, 1.2, 1.2),
		Vector3.new(x, gy + 5.5, z),
		Color3.fromRGB(255, 200, 120),
		Enum.Material.Neon,
		model
	)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 100)
	light.Range = 15
	light.Brightness = 1.2
	light.Parent = lampHead

	-- Cap
	part(
		Vector3.new(1.6, 0.3, 1.6),
		Vector3.new(x, gy + 6.2, z),
		Color3.fromRGB(50, 50, 60),
		Enum.Material.Metal,
		model
	)

	if parent then
		model.Parent = parent
	else
		model.Parent = workspace
	end
	return model
end

-- // Entrance Archway ---------------------------------------------------------------
function WorldDesign.BuildArchway(): Model
	local model = Instance.new("Model")
	model.Name = "EntranceArch"
	-- Placed south of plaza (spawn approach)
	local ax, az = CENTER_X, CENTER_Z + 25
	local gy = groundY(ax, az)

	-- Two pillars
	for _, dx in ipairs({ -5, 5 }) do
		-- Base
		part(
			Vector3.new(2, 1, 2),
			Vector3.new(ax + dx, gy + 0.5, az),
			Color3.fromRGB(130, 130, 145),
			Enum.Material.Marble,
			model
		)
		-- Pillar
		part(
			Vector3.new(1.2, 8, 1.2),
			Vector3.new(ax + dx, gy + 5, az),
			Color3.fromRGB(150, 150, 165),
			Enum.Material.Marble,
			model
		)
		-- Capital
		part(
			Vector3.new(1.8, 0.8, 1.8),
			Vector3.new(ax + dx, gy + 9.2, az),
			Color3.fromRGB(130, 130, 145),
			Enum.Material.Marble,
			model
		)
		-- Torch on top
		local torch = part(
			Vector3.new(0.6, 1.5, 0.6),
			Vector3.new(ax + dx, gy + 10.2, az),
			Color3.fromRGB(80, 50, 30),
			Enum.Material.Wood,
			model
		)
		local flame = Instance.new("ParticleEmitter")
		flame.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		flame.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 50)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 100)),
		})
		flame.Size = NumberSequence.new(1)
		flame.Speed = NumberRange.new(3, 5)
		flame.Lifetime = NumberRange.new(0.5, 0.8)
		flame.Rate = 20
		flame.Parent = torch
		local tlight = Instance.new("PointLight")
		tlight.Color = Color3.fromRGB(255, 150, 50)
		tlight.Range = 10
		tlight.Brightness = 1.5
		tlight.Parent = torch
	end

	-- Top beam
	part(
		Vector3.new(12, 1.5, 2),
		Vector3.new(ax, gy + 10, az),
		Color3.fromRGB(140, 140, 155),
		Enum.Material.Marble,
		model
	)

	-- (Title sign removed per playtest feedback — the arch stands alone.)
	model.Parent = workspace
	return model
end

-- // Pathways -----------------------------------------------------------------------
-- Stone path from point A to point B.
function WorldDesign.BuildPath(x1: number, z1: number, x2: number, z2: number)
	local model = Instance.new("Model")
	model.Name = "Pathway"

	local dx = x2 - x1
	local dz = z2 - z1
	local dist = math.sqrt(dx * dx + dz * dz)
	local steps = math.floor(dist / 3)

	for i = 0, steps do
		local t = i / steps
		local x = x1 + dx * t + (math.random() - 0.5) * 1.5
		local z = z1 + dz * t + (math.random() - 0.5) * 1.5
		local gy = groundY(x, z)
		local stone = part(
			Vector3.new(2.5 + math.random() * 1, 0.4, 2.5 + math.random() * 1),
			Vector3.new(x, gy + 0.2, z),
			Color3.fromRGB(135 + math.random(20), 135 + math.random(20), 145 + math.random(20)),
			Enum.Material.Cobblestone,
			model
		)
		stone.Rotation = Vector3.new(0, math.random(360), 0)
	end

	model.Parent = workspace
	return model
end

-- Build all pathways connecting key areas.
function WorldDesign.BuildAllPaths()
	local cx, cz = CENTER_X, CENTER_Z
	-- Plaza to arena (north)
	WorldDesign.BuildPath(cx, cz - 18, 127, 35)
	-- Plaza to plots (plots are along X at z~98)
	WorldDesign.BuildPath(cx - 18, cz, 60, cz)
	WorldDesign.BuildPath(cx + 18, cz, 200, cz)
	-- Plaza to docks
	WorldDesign.BuildPath(cx - 10, cz + 10, 100, 118)
	WorldDesign.BuildPath(cx + 10, cz + 10, 160, 128)
	-- Plaza to portals
	WorldDesign.BuildPath(cx + 15, cz - 5, 185, 80)
	-- Plaza to archway (south)
	WorldDesign.BuildPath(cx, cz + 18, cx, cz + 25)
end

-- // Landscaping --------------------------------------------------------------------
-- Flower bed: colorful flowers in a patch.
function WorldDesign.BuildFlowerBed(x: number, z: number, parent: Instance?)
	local model = Instance.new("Model")
	model.Name = "FlowerBed"
	local gy = groundY(x, z)

	-- Soil base
	local soil = part(
		Vector3.new(6, 0.6, 6),
		Vector3.new(x, gy + 0.3, z),
		Color3.fromRGB(90, 60, 40),
		Enum.Material.Grass,
		model
	)
	soil.Shape = Enum.PartType.Cylinder

	-- Flowers
	local colors = {
		Color3.fromRGB(255, 100, 150),
		Color3.fromRGB(255, 200, 80),
		Color3.fromRGB(150, 100, 255),
		Color3.fromRGB(255, 255, 255),
		Color3.fromRGB(255, 80, 80),
	}
	for i = 1, 12 do
		local fx = x + (math.random() - 0.5) * 5
		local fz = z + (math.random() - 0.5) * 5
		-- Stem
		part(
			Vector3.new(0.15, 1, 0.15),
			Vector3.new(fx, gy + 1, fz),
			Color3.fromRGB(60, 140, 60),
			Enum.Material.Grass,
			model
		)
		-- Bloom
		local bloom = part(
			Vector3.new(0.6, 0.6, 0.6),
			Vector3.new(fx, gy + 1.6, fz),
			colors[math.random(#colors)],
			Enum.Material.Neon,
			model
		)
		bloom.Shape = Enum.PartType.Ball
	end

	if parent then model.Parent = parent else model.Parent = workspace end
	return model
end

-- Hedge row: green bushes.
function WorldDesign.BuildHedge(x1: number, z1: number, x2: number, z2: number, parent: Instance?)
	local model = Instance.new("Model")
	model.Name = "Hedge"
	local dx = x2 - x1
	local dz = z2 - z1
	local dist = math.sqrt(dx * dx + dz * dz)
	local count = math.floor(dist / 3)

	for i = 0, count do
		local t = i / count
		local x = x1 + dx * t
		local z = z1 + dz * t
		local gy = groundY(x, z)
		local bush = part(
			Vector3.new(2.5, 2, 2.5),
			Vector3.new(x, gy + 1, z),
			Color3.fromRGB(45, 120, 50),
			Enum.Material.Grass,
			model
		)
		bush.Shape = Enum.PartType.Ball
	end

	if parent then model.Parent = parent else model.Parent = workspace end
	return model
end

-- Decorative tree.
function WorldDesign.BuildTree(x: number, z: number, parent: Instance?)
	local model = Instance.new("Model")
	model.Name = "DecorTree"
	local gy = groundY(x, z)
	local height = 6 + math.random(4)

	-- Trunk
	part(
		Vector3.new(1, height, 1),
		Vector3.new(x, gy + height / 2, z),
		Color3.fromRGB(100, 70, 40),
		Enum.Material.Wood,
		model
	)
	-- Canopy (3 layers)
	for i, s in ipairs({ 5, 4, 3 }) do
		local canopy = part(
			Vector3.new(s, s * 0.8, s),
			Vector3.new(x, gy + height + (i - 2) * 1.5, z),
			Color3.fromRGB(40 + math.random(20), 110 + math.random(30), 45),
			Enum.Material.Grass,
			model
		)
		canopy.Shape = Enum.PartType.Ball
	end

	if parent then model.Parent = parent else model.Parent = workspace end
	return model
end

-- Build landscaping around plaza and paths.
function WorldDesign.BuildLandscaping()
	local cx, cz = CENTER_X, CENTER_Z
	local model = Instance.new("Model")
	model.Name = "Landscaping"

	-- Flower beds around plaza
	for i = 0, 5 do
		local angle = math.rad(i * 60 + 30)
		local fx = cx + math.cos(angle) * 22
		local fz = cz + math.sin(angle) * 22
		WorldDesign.BuildFlowerBed(fx, fz, model)
	end

	-- Trees scattered (avoiding gameplay areas)
	local treeSpots = {
		{ 80, 60 }, { 170, 60 }, { 60, 130 }, { 190, 130 },
		{ 90, 40 }, { 160, 40 }, { 220, 100 }, { 40, 100 },
	}
	for _, spot in ipairs(treeSpots) do
		WorldDesign.BuildTree(spot[1], spot[2], model)
	end

	-- Hedges along plaza edge
	WorldDesign.BuildHedge(cx - 20, cz - 20, cx + 20, cz - 20, model)
	WorldDesign.BuildHedge(cx - 20, cz + 20, cx - 20, cz - 20, model)
	WorldDesign.BuildHedge(cx + 20, cz + 20, cx + 20, cz - 20, model)

	-- Extra lamps along paths
	WorldDesign.BuildLamp(127, groundY(127, 50), 50, model)
	WorldDesign.BuildLamp(100, groundY(100, 110), 110, model)
	WorldDesign.BuildLamp(185, groundY(185, 85), 85, model)

	model.Parent = workspace
	return model
end

-- // Ambient Life -------------------------------------------------------------------
-- Fireflies (appear at night via day/night cycle).
function WorldDesign.BuildFireflies()
	local model = Instance.new("Model")
	model.Name = "Fireflies"
	local cx, cz = CENTER_X, CENTER_Z

	for i = 1, 30 do
		local x = cx + (math.random() - 0.5) * 100
		local z = cz + (math.random() - 0.5) * 100
		local gy = groundY(x, z)
		local firefly = part(
			Vector3.new(0.3, 0.3, 0.3),
			Vector3.new(x, gy + 3 + math.random(4), z),
			Color3.fromRGB(255, 255, 150),
			Enum.Material.Neon,
			model
		)
		firefly.Shape = Enum.PartType.Ball
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 255, 150)
		light.Range = 5
		light.Brightness = 0.8
		light.Parent = firefly

		-- Wander animation
		task.spawn(function()
			local basePos = firefly.Position
			while firefly and firefly.Parent do
				local t = os.clock()
				firefly.Position = basePos + Vector3.new(
					math.sin(t * 0.5 + i) * 3,
					math.sin(t * 0.8 + i * 2) * 1.5,
					math.cos(t * 0.5 + i) * 3
				)
				-- Blink
				light.Brightness = 0.3 + math.abs(math.sin(t * 2 + i)) * 0.8
				task.wait(0.1)
			end
		end)
	end

	model.Parent = workspace
	return model
end

-- Butterflies (daytime).
function WorldDesign.BuildButterflies()
	local model = Instance.new("Model")
	model.Name = "Butterflies"
	local cx, cz = CENTER_X, CENTER_Z

	local colors = {
		Color3.fromRGB(255, 150, 200),
		Color3.fromRGB(150, 200, 255),
		Color3.fromRGB(255, 220, 150),
		Color3.fromRGB(200, 150, 255),
	}

	for i = 1, 15 do
		local x = cx + (math.random() - 0.5) * 80
		local z = cz + (math.random() - 0.5) * 80
		local gy = groundY(x, z)
		local bf = part(
			Vector3.new(0.8, 0.2, 0.6),
			Vector3.new(x, gy + 4 + math.random(3), z),
			colors[math.random(#colors)],
			Enum.Material.Neon,
			model
		)

		task.spawn(function()
			local basePos = bf.Position
			while bf and bf.Parent do
				local t = os.clock()
				bf.Position = basePos + Vector3.new(
					math.sin(t * 0.7 + i * 3) * 5,
					math.sin(t * 1.2 + i) * 1,
					math.cos(t * 0.6 + i * 2) * 5
				)
				bf.Rotation = Vector3.new(
					0,
					math.deg(math.atan2(
						math.cos(t * 0.7 + i * 3),
						-math.sin(t * 0.6 + i * 2)
					)),
					math.sin(t * 10 + i) * 30 -- wing flap
				)
				task.wait(0.05)
			end
		end)
	end

	model.Parent = workspace
	return model
end

-- // Lighting Overhaul ---------------------------------------------------------------
function WorldDesign.ApplyLighting()
	local lighting = game:GetService("Lighting")

	-- Warmer, more vibrant base
	lighting.Brightness = 2.2
	lighting.Ambient = Color3.fromRGB(90, 90, 110)
	lighting.OutdoorAmbient = Color3.fromRGB(110, 110, 130)
	lighting.ColorShift_Top = Color3.fromRGB(255, 240, 220)
	lighting.ColorShift_Bottom = Color3.fromRGB(180, 200, 220)

	-- Enhanced atmosphere
	local atmo = lighting:FindFirstChildOfClass("Atmosphere")
	if not atmo then
		atmo = Instance.new("Atmosphere")
		atmo.Parent = lighting
	end
	atmo.Density = 0.35
	atmo.Offset = 0.2
	atmo.Color = Color3.fromRGB(200, 220, 255)
	atmo.Decay = Color3.fromRGB(150, 180, 220)
	atmo.Glare = 0.3
	atmo.Haze = 2

	-- Bloom for glow
	local bloom = lighting:FindFirstChildOfClass("BloomEffect")
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Parent = lighting
	end
	bloom.Intensity = 0.4
	bloom.Size = 24
	bloom.Threshold = 0.85

	-- Subtle color correction
	local cc = lighting:FindFirstChildOfClass("ColorCorrectionEffect")
	if not cc then
		cc = Instance.new("ColorCorrectionEffect")
		cc.Parent = lighting
	end
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.TintColor = Color3.fromRGB(255, 250, 240)
end

-- // Main entry ----------------------------------------------------------------------
function WorldDesign.Setup()
	WorldDesign.ApplyLighting()
	WorldDesign.BuildPlaza()
	WorldDesign.BuildArchway()
	WorldDesign.BuildAllPaths()
	WorldDesign.BuildLandscaping()
	WorldDesign.BuildFireflies()
	WorldDesign.BuildButterflies()
end

return WorldDesign
