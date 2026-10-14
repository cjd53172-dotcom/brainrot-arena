--!strict
--[[
	VisualEffects (ModuleScript -> ServerScriptService/Systems)
	High-quality 3D visuals: eggs, hatching, zone portals, gold mine,
	plot themes, decorations, material models, expedition animations.
]]

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))

local VisualEffects = {}

-- // 3D Eggs ----------------------------------------------------------------------
-- Build a tier-specific egg model. Returns the Model.
function VisualEffects.BuildEgg(tierId: string): Model
	local tierDef = BrainrotData.EGG_TIERS[tierId]
	local model = Instance.new("Model")
	model.Name = "Egg_" .. tierId

	local egg = Instance.new("Part")
	egg.Name = "Shell"
	egg.Shape = Enum.PartType.Ball
	egg.Size = Vector3.new(3, 4, 3)
	egg.Anchored = true
	egg.CanCollide = false
	egg.Parent = model

	if tierId == "small" then
		-- Stone egg: rough, earthy
		egg.Color = Color3.fromRGB(140, 130, 115)
		egg.Material = Enum.Material.Slate
	elseif tierId == "big" then
		-- Blue egg: smooth with glow
		egg.Color = Color3.fromRGB(100, 160, 230)
		egg.Material = Enum.Material.SmoothPlastic
		-- Subtle glow
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(100, 160, 255)
		light.Range = 8
		light.Brightness = 1
		light.Parent = egg
		-- Crack lines (thin dark parts)
		for i = 1, 3 do
			local crack = Instance.new("Part")
			crack.Size = Vector3.new(0.1, 2, 0.1)
			crack.Color = Color3.fromRGB(40, 60, 90)
			crack.Anchored = true
			crack.CanCollide = false
			local angle = (i / 3) * math.pi * 2
			crack.Position = egg.Position + Vector3.new(math.cos(angle) * 1.2, 0.5, math.sin(angle) * 1.2)
			crack.Rotation = Vector3.new(0, math.deg(angle), 15)
			crack.Parent = model
		end
	elseif tierId == "golden" then
		-- Golden egg: metallic with sparkles and pulsing
		egg.Color = Color3.fromRGB(255, 200, 60)
		egg.Material = Enum.Material.Metal
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 80)
		light.Range = 12
		light.Brightness = 2
		light.Parent = egg
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 220, 120)
		sparkles.Parent = egg
		-- Golden bands
		for i = 1, 2 do
			local band = Instance.new("Part")
			band.Size = Vector3.new(3.1, 0.3, 3.1)
			band.Shape = Enum.PartType.Ball
			band.Color = Color3.fromRGB(200, 150, 40)
			band.Material = Enum.Material.Metal
			band.Anchored = true
			band.CanCollide = false
			band.Position = egg.Position + Vector3.new(0, (i - 1.5) * 1.2, 0)
			band.Parent = model
		end
	end

	-- Nest base
	local nest = Instance.new("Part")
	nest.Name = "Nest"
	nest.Size = Vector3.new(5, 1, 5)
	nest.Shape = Enum.PartType.Cylinder
	nest.Color = Color3.fromRGB(110, 75, 40)
	nest.Material = Enum.Material.Wood
	nest.Anchored = true
	nest.CanCollide = false
	nest.Position = egg.Position - Vector3.new(0, 2.2, 0)
	nest.Parent = model

	model.PrimaryPart = egg
	return model
end

-- Hatching animation: shake -> crack -> burst -> reveal.
-- onComplete called when brainrot should appear.
function VisualEffects.PlayHatch(eggModel: Model, onComplete: () -> ())
	local shell = eggModel:FindFirstChild("Shell")
	if not shell or not shell:IsA("BasePart") then
		onComplete()
		return
	end
	local eggPos = (shell :: BasePart).Position

	-- Phase 1: Shaking (2 seconds, increasing intensity)
	for i = 1, 20 do
		local intensity = i / 20 * 0.5
		local offset = Vector3.new(
			math.random() * intensity - intensity/2,
			0,
			math.random() * intensity - intensity/2
		)
		eggModel:PivotTo(CFrame.new(eggPos + offset))
		task.wait(0.1)
	end

	-- Phase 2: Light burst
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 255, 200)
	flash.Range = 20
	flash.Brightness = 5
	flash.Parent = shell

	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new(Color3.fromRGB(255, 240, 180))
	burst.Size = NumberSequence.new(1.5)
	burst.Speed = NumberRange.new(10, 20)
	burst.Lifetime = NumberRange.new(0.5, 1)
	burst.Rate = 100
	burst.Parent = shell
	task.wait(0.3)
	burst.Rate = 0

	-- Phase 3: Shell breaks apart
	for _, part in ipairs(eggModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Name ~= "Nest" then
			part.Anchored = false
			part.CanCollide = false
			local bv = Instance.new("BodyVelocity")
			bv.Velocity = Vector3.new(
				math.random(-15, 15),
				math.random(10, 25),
				math.random(-15, 15)
			)
			bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
			bv.Parent = part
			task.delay(2, function()
				if part and part.Parent then
					part:Destroy()
				end
				if bv and bv.Parent then
					bv:Destroy()
				end
			end)
		end
	end

	task.wait(0.5)
	onComplete()

	-- Cleanup
	task.delay(3, function()
		if eggModel and eggModel.Parent then
			eggModel:Destroy()
		end
	end)
end

-- // Zone Portals ---------------------------------------------------------------------
-- Build a themed portal for a zone. Returns the Model.
function VisualEffects.BuildZonePortal(zoneId: string): Model
	local zone = BrainrotData.ZONES[zoneId]
	local model = Instance.new("Model")
	model.Name = "Portal_" .. zoneId

	local baseColor = zone and zone.Color or Color3.fromRGB(100, 100, 100)

	-- Arch frame (two pillars + top)
	for _, xOffset in ipairs({ -4, 4 }) do
		local pillar = Instance.new("Part")
		pillar.Size = Vector3.new(2, 12, 2)
		pillar.Anchored = true
		pillar.Color = baseColor
		pillar.Material = Enum.Material.Stone
		pillar.Position = Vector3.new(xOffset, 6, 0)
		pillar.Parent = model

		-- Theme-specific pillar tops
		if zoneId == "whispering_woods" then
			-- Vines
			local leaves = Instance.new("Part")
			leaves.Size = Vector3.new(3, 3, 3)
			leaves.Shape = Enum.PartType.Ball
			leaves.Color = Color3.fromRGB(45, 130, 70)
			leaves.Material = Enum.Material.Grass
			leaves.Anchored = true
			leaves.Position = Vector3.new(xOffset, 13, 0)
			leaves.Parent = model
		elseif zoneId == "ember_peaks" then
			-- Lava glow
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(255, 100, 30)
			glow.Range = 10
			glow.Brightness = 2
			glow.Parent = pillar
		elseif zoneId == "crystal_caves" then
			-- Crystal shards
			local shard = Instance.new("Part")
			shard.Size = Vector3.new(1, 4, 1)
			shard.Color = Color3.fromRGB(150, 200, 255)
			shard.Material = Enum.Material.Glass
			shard.Anchored = true
			shard.Position = Vector3.new(xOffset, 14, 0)
			shard.Rotation = Vector3.new(15, 0, 10)
			shard.Parent = model
		end
	end

	-- Top beam
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(10, 2, 2)
	beam.Anchored = true
	beam.Color = baseColor
	beam.Material = Enum.Material.Stone
	beam.Position = Vector3.new(0, 12.5, 0)
	beam.Parent = model

	-- Portal surface (glowing)
	local portal = Instance.new("Part")
	portal.Name = "PortalSurface"
	portal.Size = Vector3.new(6, 10, 0.5)
	portal.Anchored = true
	portal.CanCollide = false
	portal.Color = baseColor
	portal.Material = Enum.Material.Neon
	portal.Transparency = 0.3
	portal.Position = Vector3.new(0, 6, 0)
	portal.Parent = model

	-- Swirling particles
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new(baseColor)
	particles.Size = NumberSequence.new(0.8)
	particles.Speed = NumberRange.new(2, 5)
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 20
	particles.RotSpeed = NumberRange.new(-90, 90)
	particles.Parent = portal

	-- Light
	local light = Instance.new("PointLight")
	light.Color = baseColor
	light.Range = 15
	light.Brightness = 2
	light.Parent = portal

	-- Zone name sign
	local sign = Instance.new("Part")
	sign.Size = Vector3.new(8, 2, 0.5)
	sign.Anchored = true
	sign.Color = Color3.fromRGB(60, 40, 20)
	sign.Material = Enum.Material.Wood
	sign.Position = Vector3.new(0, 15, 0)
	sign.Parent = model

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = zone and zone.Name or "???"
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextSize = 24
	signLabel.TextColor3 = Color3.new(1, 1, 1)
	signLabel.TextStrokeTransparency = 0.5
	signLabel.Parent = signGui

	model.PrimaryPart = portal
	return model
end

-- // Gold Mine (detailed) ----------------------------------------------------------------
function VisualEffects.BuildGoldMine(level: number): Model
	local model = Instance.new("Model")
	model.Name = "GoldMine"

	-- Rock base
	local rock = Instance.new("Part")
	rock.Size = Vector3.new(10, 6, 8)
	rock.Shape = Enum.PartType.Ball
	rock.Color = Color3.fromRGB(100, 95, 90)
	rock.Material = Enum.Material.Slate
	rock.Anchored = true
	rock.Position = Vector3.new(0, 2, 0)
	rock.Parent = model

	-- Mine entrance (dark opening)
	local entrance = Instance.new("Part")
	entrance.Size = Vector3.new(4, 4, 1)
	entrance.Color = Color3.fromRGB(20, 15, 10)
	entrance.Anchored = true
	entrance.Position = Vector3.new(0, 2, 4)
	entrance.Parent = model

	-- Wooden support beams
	for _, x in ipairs({ -2.5, 2.5 }) do
		for _, y in ipairs({ 0.5, 3.5 }) do
			local beam = Instance.new("Part")
			beam.Size = Vector3.new(0.5, 0.5, 5)
			beam.Color = Color3.fromRGB(110, 75, 40)
			beam.Material = Enum.Material.Wood
			beam.Anchored = true
			beam.Position = Vector3.new(x, y, 2)
			beam.Parent = model
		end
	end

	-- Gold veins (glowing spots on rock)
	local veinCount = 2 + level -- more veins at higher levels
	for i = 1, veinCount do
		local vein = Instance.new("Part")
		vein.Size = Vector3.new(1, 1, 0.5)
		vein.Color = Color3.fromRGB(255, 200, 60)
		vein.Material = Enum.Material.Neon
		vein.Anchored = true
		local angle = (i / veinCount) * math.pi * 2
		vein.Position = Vector3.new(
			math.cos(angle) * 4,
			2 + math.sin(angle * 2) * 1.5,
			math.sin(angle) * 3 + 1
		)
		vein.Parent = model

		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 200, 80)
		glow.Range = 6
		glow.Brightness = 1
		glow.Parent = vein
	end

	-- Minecart
	local cart = Instance.new("Part")
	cart.Name = "Cart"
	cart.Size = Vector3.new(3, 1.5, 2)
	cart.Color = Color3.fromRGB(80, 60, 40)
	cart.Material = Enum.Material.Wood
	cart.Anchored = true
	cart.Position = Vector3.new(0, 0.8, 7)
	cart.Parent = model

	-- Gold in cart
	local goldPile = Instance.new("Part")
	goldPile.Size = Vector3.new(2, 0.8, 1.5)
	goldPile.Shape = Enum.PartType.Ball
	goldPile.Color = Color3.fromRGB(255, 200, 60)
	goldPile.Material = Enum.Material.Metal
	goldPile.Anchored = true
	goldPile.Position = Vector3.new(0, 1.8, 7)
	goldPile.Parent = model

	-- Rails
	for _, x in ipairs({ -1, 1 }) do
		local rail = Instance.new("Part")
		rail.Size = Vector3.new(0.3, 0.3, 10)
		rail.Color = Color3.fromRGB(120, 120, 120)
		rail.Material = Enum.Material.Metal
		rail.Anchored = true
		rail.Position = Vector3.new(x, 0.2, 5)
		rail.Parent = model
	end

	-- Floating coin particles
	local coins = Instance.new("ParticleEmitter")
	coins.Texture = "rbxassetid://6834885264" -- coin texture
	coins.Color = ColorSequence.new(Color3.fromRGB(255, 210, 100))
	coins.Size = NumberSequence.new(0.8)
	coins.Speed = NumberRange.new(2, 4)
	coins.Lifetime = NumberRange.new(1.5, 2.5)
	coins.Rate = 5 + level * 2
	coins.Parent = goldPile

	model.PrimaryPart = rock
	return model
end

-- // Plot Themes (full visual) ---------------------------------------------------------------
function VisualEffects.ApplyTheme(plot: Model, themeId: string)
	local theme = BrainrotData.PLOT_THEMES[themeId]
	if not theme then return end

	-- Clear old theme effects
	local oldFx = plot:FindFirstChild("ThemeFX")
	if oldFx then oldFx:Destroy() end
	local fxFolder = Instance.new("Folder")
	fxFolder.Name = "ThemeFX"
	fxFolder.Parent = plot

	local base = plot:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then return end
	local bp = (base :: BasePart).Position
	local bs = (base :: BasePart).Size

	-- Base color
	(base :: BasePart).Color = theme.Color;

	if themeId == "crystal" then
		-- Glass shards + blue lighting
		for i = 1, 8 do
			local shard = Instance.new("Part")
			shard.Size = Vector3.new(1, 3 + math.random() * 3, 1)
			shard.Color = Color3.fromRGB(150, 200, 255)
			shard.Material = Enum.Material.Glass
			shard.Transparency = 0.3
			shard.Anchored = true
			shard.Position = Vector3.new(
				bp.X + (math.random() - 0.5) * bs.X * 0.8,
				bp.Y + 2,
				bp.Z + (math.random() - 0.5) * bs.Z * 0.8
			)
			shard.Rotation = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
			shard.Parent = fxFolder
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 200, 255)
		light.Range = 30
		light.Brightness = 1.5
		light.Position = bp + Vector3.new(0, 10, 0)
		light.Parent = fxFolder

	elseif themeId == "volcanic" then
		-- Lava cracks + ember particles
		(base :: BasePart).Material = Enum.Material.CrackedLava
		for i = 1, 5 do
			local ember = Instance.new("ParticleEmitter")
			ember.Texture = "rbxasset://textures/particles/fire_main.dds"
			ember.Color = ColorSequence.new(Color3.fromRGB(255, 100, 30))
			ember.Size = NumberSequence.new(0.5)
			ember.Speed = NumberRange.new(3, 6)
			ember.Lifetime = NumberRange.new(1, 2)
			ember.Rate = 10
			ember.Parent = base
			-- Position handled by parent
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 100, 30)
		light.Range = 25
		light.Brightness = 2
		light.Position = bp + Vector3.new(0, 8, 0)
		light.Parent = fxFolder

	elseif themeId == "ocean" then
		-- Water ripples + blue fog
		(base :: BasePart).Material = Enum.Material.Water
		(base :: BasePart).Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(50, 130, 180)
		light.Range = 25
		light.Brightness = 1.5
		light.Position = bp + Vector3.new(0, 8, 0)
		light.Parent = fxFolder

	elseif themeId == "shadow" then
		-- Dark fog + purple wisps
		(base :: BasePart).Color = Color3.fromRGB(40, 40, 60)
		local fog = Instance.new("ParticleEmitter")
		fog.Texture = "rbxasset://textures/particles/smoke_main.dds"
		fog.Color = ColorSequence.new(Color3.fromRGB(60, 40, 90))
		fog.Size = NumberSequence.new(3)
		fog.Speed = NumberRange.new(1, 2)
		fog.Lifetime = NumberRange.new(3, 5)
		fog.Rate = 8
		fog.Transparency = NumberSequence.new(0.5)
		fog.Parent = base
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(100, 60, 150)
		light.Range = 20
		light.Brightness = 1
		light.Position = bp + Vector3.new(0, 8, 0)
		light.Parent = fxFolder
	end
end

-- // Detailed Decorations --------------------------------------------------------------------
function VisualEffects.BuildDecoration(decoId: string): Model
	local model = Instance.new("Model")
	model.Name = "Deco_" .. decoId

	if decoId == "banner" then
		-- Pole + waving banner
		local pole = Instance.new("Part")
		pole.Size = Vector3.new(0.5, 10, 0.5)
		pole.Color = Color3.fromRGB(80, 55, 30)
		pole.Material = Enum.Material.Wood
		pole.Anchored = true
		pole.Position = Vector3.new(0, 5, 0)
		pole.Parent = model

		local cloth = Instance.new("Part")
		cloth.Name = "Cloth"
		cloth.Size = Vector3.new(4, 3, 0.2)
		cloth.Color = Color3.fromRGB(200, 50, 50)
		cloth.Material = Enum.Material.Fabric
		cloth.Anchored = true
		cloth.Position = Vector3.new(2.2, 8, 0)
		cloth.Parent = model

		-- Gold trim
		local trim = Instance.new("Part")
		trim.Size = Vector3.new(4.2, 0.3, 0.3)
		trim.Color = Color3.fromRGB(255, 200, 60)
		trim.Material = Enum.Material.Metal
		trim.Anchored = true
		trim.Position = Vector3.new(2.2, 6.6, 0)
		trim.Parent = model

		-- Wave animation
		task.spawn(function()
			while cloth and cloth.Parent do
				local t = os.clock()
				cloth.Rotation = Vector3.new(0, math.sin(t * 3) * 10, 0)
				task.wait(0.05)
			end
		end)

	elseif decoId == "fountain" then
		-- Tiered fountain with animated water
		for i, size in ipairs({ 6, 4, 2 }) do
			local tier = Instance.new("Part")
			tier.Size = Vector3.new(size, 1, size)
			tier.Shape = Enum.PartType.Cylinder
			tier.Color = Color3.fromRGB(180, 180, 190)
			tier.Material = Enum.Material.Marble
			tier.Anchored = true
			tier.Position = Vector3.new(0, i * 1.5, 0)
			tier.Parent = model

			local water = Instance.new("Part")
			water.Size = Vector3.new(size - 0.5, 0.3, size - 0.5)
			water.Shape = Enum.PartType.Cylinder
			water.Color = Color3.fromRGB(100, 180, 230)
			water.Material = Enum.Material.Water
			water.Transparency = 0.3
			water.Anchored = true
			water.Position = Vector3.new(0, i * 1.5 + 0.6, 0)
			water.Parent = model
		end
		-- Water spray particles
		local spray = Instance.new("ParticleEmitter")
		spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		spray.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
		spray.Size = NumberSequence.new(0.4)
		spray.Speed = NumberRange.new(5, 8)
		spray.Lifetime = NumberRange.new(0.8, 1.2)
		spray.Rate = 30
		spray.Parent = model:FindFirstChildOfClass("Part")

	elseif decoId == "torch" then
		-- Stone base + wooden post + flame
		local basePart = Instance.new("Part")
		basePart.Size = Vector3.new(2, 1, 2)
		basePart.Color = Color3.fromRGB(100, 100, 100)
		basePart.Material = Enum.Material.Stone
		basePart.Anchored = true
		basePart.Position = Vector3.new(0, 0.5, 0)
		basePart.Parent = model

		local post = Instance.new("Part")
		post.Size = Vector3.new(0.6, 5, 0.6)
		post.Color = Color3.fromRGB(90, 60, 35)
		post.Material = Enum.Material.Wood
		post.Anchored = true
		post.Position = Vector3.new(0, 3.5, 0)
		post.Parent = model

		local cup = Instance.new("Part")
		cup.Size = Vector3.new(1.5, 0.8, 1.5)
		cup.Shape = Enum.PartType.Cylinder
		cup.Color = Color3.fromRGB(60, 60, 60)
		cup.Material = Enum.Material.Metal
		cup.Anchored = true
		cup.Position = Vector3.new(0, 6.2, 0)
		cup.Parent = model

		local fire = Instance.new("Fire")
		fire.Size = 8
		fire.Heat = 10
		fire.Parent = cup

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 50)
		light.Range = 12
		light.Brightness = 2
		light.Parent = cup

	elseif decoId == "crystal_deco" then
		-- Cluster of crystals
		for i = 1, 5 do
			local crystal = Instance.new("Part")
			local h = 2 + math.random() * 3
			crystal.Size = Vector3.new(0.8, h, 0.8)
			crystal.Color = Color3.fromRGB(150, 200, 255)
			crystal.Material = Enum.Material.Glass
			crystal.Transparency = 0.2
			crystal.Anchored = true
			local angle = (i / 5) * math.pi * 2
			crystal.Position = Vector3.new(
				math.cos(angle) * 1.5,
				h / 2,
				math.sin(angle) * 1.5
			)
			crystal.Rotation = Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
			crystal.Parent = model
		end
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(150, 200, 255)
		glow.Range = 10
		glow.Brightness = 1.5
		glow.Position = Vector3.new(0, 3, 0)
		glow.Parent = model

	elseif decoId == "statue" then
		-- Pedestal + golden brainrot silhouette
		local ped = Instance.new("Part")
		ped.Size = Vector3.new(3, 2, 3)
		ped.Color = Color3.fromRGB(120, 120, 130)
		ped.Material = Enum.Material.Marble
		ped.Anchored = true
		ped.Position = Vector3.new(0, 1, 0)
		ped.Parent = model

		local figure = Instance.new("Part")
		figure.Size = Vector3.new(1.5, 4, 1.5)
		figure.Shape = Enum.PartType.Ball
		figure.Color = Color3.fromRGB(255, 200, 60)
		figure.Material = Enum.Material.Metal
		figure.Anchored = true
		figure.Position = Vector3.new(0, 4.5, 0)
		figure.Parent = model

		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 220, 120)
		sparkles.Parent = figure
	end

	return model
end

-- // Material Models (3D pickups) ---------------------------------------------------------------
function VisualEffects.BuildMaterial(matName: string): Model
	local model = Instance.new("Model")
	model.Name = "Mat_" .. matName

	local color = BrainrotData.RARE_MATERIALS[matName] or Color3.fromRGB(150, 150, 150)

	local part = Instance.new("Part")
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.5, 1.5, 1.5)
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.Parent = model

	-- Shape variations by material type
	if string.find(matName, "Shard") or string.find(matName, "Crystal") then
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(0.8, 1.8, 0.8)
		part.Rotation = Vector3.new(15, 0, 10)
		part.Material = Enum.Material.Glass
		part.Transparency = 0.2
	elseif string.find(matName, "Essence") or string.find(matName, "Core") then
		part.Shape = Enum.PartType.Ball
		local glow = Instance.new("PointLight")
		glow.Color = color
		glow.Range = 6
		glow.Brightness = 1.5
		glow.Parent = part
	elseif matName == "Sunken Gold" then
		part.Shape = Enum.PartType.Cylinder
		part.Size = Vector3.new(1.2, 0.5, 1.2)
		part.Material = Enum.Material.Metal
	end

	-- Float + spin animation
	task.spawn(function()
		local baseY = part.Position.Y
		while part and part.Parent do
			local t = os.clock()
			part.Position = Vector3.new(
				part.Position.X,
				baseY + math.sin(t * 2) * 0.3,
				part.Position.Z
			)
			part.Rotation = Vector3.new(0, math.deg(t * 1.5) % 360, 0)
			task.wait(0.05)
		end
	end)

	model.PrimaryPart = part
	return model
end

-- // Expedition Departure -------------------------------------------------------------------
-- Animate team walking toward zone direction, then fade out.
function VisualEffects.PlayDeparture(models: { Model }, direction: Vector3)
	for _, model in ipairs(models) do
		task.spawn(function()
			local startPos = model:GetPivot().Position
			local targetPos = startPos + direction * 30
			-- Walk (bob) toward direction over 3 seconds
			for i = 1, 30 do
				if not model or not model.Parent then break end
				local t = i / 30
				local pos = startPos:Lerp(targetPos, t)
				-- Bobbing walk
				pos += Vector3.new(0, math.abs(math.sin(t * 20)) * 0.5, 0)
				model:PivotTo(CFrame.new(pos))
				task.wait(0.1)
			end
			-- Fade out
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then
					local tween = TweenService:Create(desc,
						TweenInfo.new(0.5),
						{ Transparency = 1 }
					)
					tween:Play()
				end
			end
			task.wait(0.6)
			if model and model.Parent then
				model:Destroy()
			end
		end)
	end
end

return VisualEffects
