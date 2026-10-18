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
		pillar.Material = Enum.Material.Slate
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
	beam.Material = Enum.Material.Slate
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

	-- Zone name sign (large, readable from a distance).
	local sign = Instance.new("Part")
	sign.Size = Vector3.new(12, 3, 0.5)
	sign.Anchored = true
	sign.Color = Color3.fromRGB(40, 30, 20)
	sign.Material = Enum.Material.Wood
	sign.Position = Vector3.new(0, 15.5, 0)
	sign.Parent = model

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "EXPEDITION GATE\n" .. (zone and zone.Name or "???")
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true -- auto-fit, always readable
	signLabel.TextColor3 = Color3.new(1, 0.9, 0.3) -- gold text
	signLabel.TextStrokeTransparency = 0.3
	signLabel.Parent = signGui

	model.PrimaryPart = portal
	return model
end

function VisualEffects.BuildPlacePortal(gateName: string, color: Color3): Model
	local model = Instance.new("Model")
	model.Name = "PlacePortal_" .. gateName
	local baseColor = color
	for _, xOffset in ipairs({ -4, 4 }) do
		local pillar = Instance.new("Part")
		pillar.Size = Vector3.new(2, 12, 2)
		pillar.Anchored = true
		pillar.Color = Color3.fromRGB(30, 40, 35)
		pillar.Material = Enum.Material.Metal
		pillar.Position = Vector3.new(xOffset, 6, 0)
		pillar.Parent = model
		local glow = Instance.new("PointLight")
		glow.Color = baseColor
		glow.Range = 12
		glow.Brightness = 2
		glow.Parent = pillar
	end
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(10, 2, 2)
	beam.Anchored = true
	beam.Color = Color3.fromRGB(30, 40, 35)
	beam.Material = Enum.Material.Metal
	beam.Position = Vector3.new(0, 12.5, 0)
	beam.Parent = model
	local portal = Instance.new("Part")
	portal.Name = "PortalSurface"
	portal.Size = Vector3.new(6, 10, 0.5)
	portal.Anchored = true
	portal.CanCollide = false
	portal.Color = baseColor
	portal.Material = Enum.Material.Neon
	portal.Transparency = 0.25
	portal.Position = Vector3.new(0, 6, 0)
	portal.Parent = model
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new(baseColor)
	particles.Size = NumberSequence.new(0.9)
	particles.Speed = NumberRange.new(2, 6)
	particles.Lifetime = NumberRange.new(1, 2)
	particles.Rate = 28
	particles.Parent = portal
	local sign = Instance.new("Part")
	sign.Size = Vector3.new(12, 3, 0.5)
	sign.Anchored = true
	sign.Color = Color3.fromRGB(20, 30, 22)
	sign.Material = Enum.Material.Metal
	sign.Position = Vector3.new(0, 15.5, 0)
	sign.Parent = model
	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "MINIGAME\n" .. gateName
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true
	signLabel.TextColor3 = baseColor
	signLabel.TextStrokeTransparency = 0.3
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
	local bp = base.Position
	local bs = base.Size

	-- Base color
	base.Color = theme.Color

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
		light.Parent = base

	elseif themeId == "volcanic" then
		-- Lava cracks + ember particles
		base.Material = Enum.Material.CrackedLava
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
		light.Parent = base

	elseif themeId == "ocean" then
		-- Water ripples + blue fog
		base.Material = Enum.Material.Water
		base.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(50, 130, 180)
		light.Range = 25
		light.Brightness = 1.5
		light.Parent = base

	elseif themeId == "shadow" then
		-- Dark fog + purple wisps
		base.Color = Color3.fromRGB(40, 40, 60)
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
		light.Parent = base
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
		basePart.Material = Enum.Material.Slate
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

	elseif decoId == "garden" then
		-- Circular flower bed with colorful flowers
		local bed = Instance.new("Part")
		bed.Size = Vector3.new(6, 1, 6)
		bed.Shape = Enum.PartType.Cylinder
		bed.Color = Color3.fromRGB(90, 60, 40)
		bed.Material = Enum.Material.Wood
		bed.Anchored = true
		bed.Position = Vector3.new(0, 0.5, 0)
		bed.Parent = model

		local soil = Instance.new("Part")
		soil.Size = Vector3.new(5.5, 0.5, 5.5)
		soil.Shape = Enum.PartType.Cylinder
		soil.Color = Color3.fromRGB(60, 40, 25)
		soil.Anchored = true
		soil.Position = Vector3.new(0, 1.1, 0)
		soil.Parent = model

		-- Flowers
		local flowerColors = {
			Color3.fromRGB(255, 100, 150),
			Color3.fromRGB(255, 200, 60),
			Color3.fromRGB(150, 100, 255),
			Color3.fromRGB(255, 255, 255),
		}
		for i = 1, 8 do
			local angle = (i / 8) * math.pi * 2
			local stem = Instance.new("Part")
			stem.Size = Vector3.new(0.2, 1.5, 0.2)
			stem.Color = Color3.fromRGB(50, 130, 60)
			stem.Anchored = true
			stem.Position = Vector3.new(math.cos(angle) * 2, 2, math.sin(angle) * 2)
			stem.Parent = model

			local bloom = Instance.new("Part")
			bloom.Size = Vector3.new(0.8, 0.8, 0.8)
			bloom.Shape = Enum.PartType.Ball
			bloom.Color = flowerColors[(i % #flowerColors) + 1]
			bloom.Anchored = true
			bloom.Position = Vector3.new(math.cos(angle) * 2, 2.8, math.sin(angle) * 2)
			bloom.Parent = model
		end

	elseif decoId == "flags" then
		-- String of pennant flags between two poles
		for _, x in ipairs({ -4, 4 }) do
			local pole = Instance.new("Part")
			pole.Size = Vector3.new(0.4, 8, 0.4)
			pole.Color = Color3.fromRGB(80, 55, 30)
			pole.Material = Enum.Material.Wood
			pole.Anchored = true
			pole.Position = Vector3.new(x, 4, 0)
			pole.Parent = model
		end
		-- Rope
		local rope = Instance.new("Part")
		rope.Size = Vector3.new(8, 0.15, 0.15)
		rope.Color = Color3.fromRGB(150, 120, 80)
		rope.Anchored = true
		rope.Position = Vector3.new(0, 7.8, 0)
		rope.Parent = model
		-- Pennants
		local pennantColors = {
			Color3.fromRGB(255, 100, 100),
			Color3.fromRGB(100, 150, 255),
			Color3.fromRGB(255, 200, 60),
			Color3.fromRGB(100, 220, 100),
		}
		for i = 1, 6 do
			local pennant = Instance.new("Part")
			pennant.Size = Vector3.new(0.8, 1.2, 0.1)
			pennant.Color = pennantColors[(i % #pennantColors) + 1]
			pennant.Material = Enum.Material.Fabric
			pennant.Anchored = true
			pennant.Position = Vector3.new(-3 + i * 1.1, 7.1, 0)
			pennant.Parent = model
			-- Wave
			task.spawn(function()
				while pennant and pennant.Parent do
					pennant.Rotation = Vector3.new(0, math.sin(os.clock() * 4 + i) * 15, 0)
					task.wait(0.05)
				end
			end)
		end

	elseif decoId == "lantern" then
		-- Floating spirit lantern
		local post = Instance.new("Part")
		post.Size = Vector3.new(0.5, 7, 0.5)
		post.Color = Color3.fromRGB(60, 60, 70)
		post.Material = Enum.Material.Metal
		post.Anchored = true
		post.Position = Vector3.new(0, 3.5, 0)
		post.Parent = model

		local arm = Instance.new("Part")
		arm.Size = Vector3.new(2.5, 0.4, 0.4)
		arm.Color = Color3.fromRGB(60, 60, 70)
		arm.Material = Enum.Material.Metal
		arm.Anchored = true
		arm.Position = Vector3.new(1, 6.8, 0)
		arm.Parent = model

		local cage = Instance.new("Part")
		cage.Name = "LanternGlow"
		cage.Size = Vector3.new(1.2, 1.6, 1.2)
		cage.Color = Color3.fromRGB(150, 200, 255)
		cage.Material = Enum.Material.Neon
		cage.Transparency = 0.3
		cage.Anchored = true
		cage.Position = Vector3.new(2, 5.8, 0)
		cage.Parent = model

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(150, 200, 255)
		light.Range = 12
		light.Brightness = 2
		light.Parent = cage

		-- Gentle float
		task.spawn(function()
			local baseY = 5.8
			while cage and cage.Parent do
				cage.Position = Vector3.new(2, baseY + math.sin(os.clock() * 1.5) * 0.3, 0)
				task.wait(0.05)
			end
		end)

	elseif decoId == "golem" then
		-- Stone guardian
		local body = Instance.new("Part")
		body.Size = Vector3.new(3, 4, 2)
		body.Color = Color3.fromRGB(100, 100, 110)
		body.Material = Enum.Material.Slate
		body.Anchored = true
		body.Position = Vector3.new(0, 3, 0)
		body.Parent = model

		local head = Instance.new("Part")
		head.Size = Vector3.new(1.8, 1.8, 1.8)
		head.Color = Color3.fromRGB(110, 110, 120)
		head.Material = Enum.Material.Slate
		head.Anchored = true
		head.Position = Vector3.new(0, 6, 0)
		head.Parent = model

		-- Glowing eyes
		for _, x in ipairs({ -0.4, 0.4 }) do
			local eye = Instance.new("Part")
			eye.Size = Vector3.new(0.3, 0.3, 0.2)
			eye.Color = Color3.fromRGB(255, 100, 50)
			eye.Material = Enum.Material.Neon
			eye.Anchored = true
			eye.Position = Vector3.new(x, 6.2, 1)
			eye.Parent = model
		end

		-- Arms
		for _, x in ipairs({ -2.2, 2.2 }) do
			local armPart = Instance.new("Part")
			armPart.Size = Vector3.new(1, 3.5, 1)
			armPart.Color = Color3.fromRGB(95, 95, 105)
			armPart.Material = Enum.Material.Slate
			armPart.Anchored = true
			armPart.Position = Vector3.new(x, 3, 0)
			armPart.Parent = model
		end
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

-- // Fusion Lab Animation ----------------------------------------------------------------------
-- 3D fusion sequence: models spin around fusion point, merge with light burst, result appears.
function VisualEffects.PlayFusion(models: { Model }, fusionPos: Vector3, resultModel: Model, onComplete: () -> ())
	-- Phase 1: Models orbit the fusion point (3 seconds)
	local orbitRadius = 8
	local orbitTime = 3
	local steps = 30
	for i = 1, steps do
		local t = i / steps
		local angle = t * math.pi * 4 -- two full rotations
		-- Spiral inward
		local radius = orbitRadius * (1 - t * 0.7)
		for j, model in ipairs(models) do
			if model and model.Parent then
				local offsetAngle = angle + (j / #models) * math.pi * 2
				local pos = fusionPos + Vector3.new(
					math.cos(offsetAngle) * radius,
					2 + math.sin(t * 10 + j) * 1,
					math.sin(offsetAngle) * radius
				)
				model:PivotTo(CFrame.new(pos))
			end
		end
		-- Rising pitch particles
		if i % 5 == 0 then
			local spark = Instance.new("ParticleEmitter")
			spark.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			spark.Color = ColorSequence.new(Color3.fromRGB(200, 150, 255))
			spark.Size = NumberSequence.new(0.8)
			spark.Speed = NumberRange.new(5, 10)
			spark.Lifetime = NumberRange.new(0.5, 1)
			spark.Rate = 30
			local anchor = Instance.new("Part")
			anchor.Size = Vector3.new(1, 1, 1)
			anchor.Transparency = 1
			anchor.Anchored = true
			anchor.CanCollide = false
			anchor.Position = fusionPos
			anchor.Parent = workspace
			spark.Parent = anchor
			task.delay(1, function()
				if anchor and anchor.Parent then anchor:Destroy() end
			end)
		end
		task.wait(orbitTime / steps)
	end

	-- Phase 2: Merge flash
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(255, 255, 255)
	flash.Range = 30
	flash.Brightness = 10
	local flashPart = Instance.new("Part")
	flashPart.Size = Vector3.new(1, 1, 1)
	flashPart.Transparency = 1
	flashPart.Anchored = true
	flashPart.Position = fusionPos
	flashPart.Parent = workspace
	flash.Parent = flashPart

	-- Destroy input models
	for _, model in ipairs(models) do
		if model and model.Parent then
			model:Destroy()
		end
	end

	-- Big burst
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	burst.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 150, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 100, 255)),
	})
	burst.Size = NumberSequence.new(2)
	burst.Speed = NumberRange.new(15, 30)
	burst.Lifetime = NumberRange.new(0.8, 1.5)
	burst.Rate = 200
	burst.Parent = flashPart
	task.wait(0.5)
	burst.Rate = 0
	flash.Brightness = 3

	-- Phase 3: Result rises from the light
	resultModel:PivotTo(CFrame.new(fusionPos - Vector3.new(0, 5, 0)))
	resultModel.Parent = workspace
	-- Start invisible, fade in while rising
	for _, desc in ipairs(resultModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = 1
		end
	end
	for i = 1, 20 do
		local t = i / 20
		local pos = (fusionPos - Vector3.new(0, 5, 0)):Lerp(fusionPos + Vector3.new(0, 2, 0), t)
		resultModel:PivotTo(CFrame.new(pos))
		for _, desc in ipairs(resultModel:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Transparency = 1 - t
			end
		end
		task.wait(0.05)
	end

	task.wait(1)
	onComplete()

	-- Cleanup
	task.delay(2, function()
		if flashPart and flashPart.Parent then flashPart:Destroy() end
		if resultModel and resultModel.Parent then resultModel:Destroy() end
	end)
end

-- // Arena Colosseum ------------------------------------------------------------------
-- Build an impressive colosseum structure for battles.
function VisualEffects.BuildColosseum(centerPos: Vector3, scale: number?): Model
	local model = Instance.new("Model")
	model.Name = "Colosseum"
	local s = scale or 1

	-- Outer wall (cylinder segments)
	local wallSegments = 16
	local radius = 30 * s
	for i = 1, wallSegments do
		local angle = (i / wallSegments) * math.pi * 2
		local wall = Instance.new("Part")
		wall.Size = Vector3.new(8 * s, 15 * s, 3 * s)
		wall.Color = Color3.fromRGB(180, 170, 160)
		wall.Material = Enum.Material.Marble
		wall.Anchored = true
		wall.Position = centerPos + Vector3.new(
			math.cos(angle) * radius,
			7.5 * s,
			math.sin(angle) * radius
		)
		wall.Orientation = Vector3.new(0, -math.deg(angle) + 90, 0)
		wall.Parent = model

		-- Arch openings (every other segment is shorter)
		if i % 2 == 0 then
			wall.Size = Vector3.new(8 * s, 8 * s, 3 * s)
			wall.Position = centerPos + Vector3.new(
				math.cos(angle) * radius,
				4 * s,
				math.sin(angle) * radius
			)
		end
	end

	-- Floor (sand)
	local floor = Instance.new("Part")
	floor.Name = "ArenaFloor"
	floor.Size = Vector3.new(radius * 2, 1, radius * 2)
	floor.Shape = Enum.PartType.Cylinder
	floor.Color = Color3.fromRGB(220, 190, 140)
	floor.Material = Enum.Material.Sand
	floor.Anchored = true
	floor.Position = centerPos
	floor.Parent = model

	-- Center emblem
	local emblem = Instance.new("Part")
	emblem.Size = Vector3.new(10 * s, 0.5 * s, 10 * s)
	emblem.Shape = Enum.PartType.Cylinder
	emblem.Color = Color3.fromRGB(200, 50, 50)
	emblem.Material = Enum.Material.Marble
	emblem.Anchored = true
	emblem.Position = centerPos + Vector3.new(0, 0.8 * s, 0)
	emblem.Parent = model

	-- Torches around the rim
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local torchPos = centerPos + Vector3.new(
			math.cos(angle) * (radius - 3 * s),
			0,
			math.sin(angle) * (radius - 3 * s)
		)
		-- Simple torch
		local post = Instance.new("Part")
		post.Size = Vector3.new(0.8 * s, 6 * s, 0.8 * s)
		post.Color = Color3.fromRGB(90, 60, 35)
		post.Material = Enum.Material.Wood
		post.Anchored = true
		post.Position = torchPos + Vector3.new(0, 3 * s, 0)
		post.Parent = model

		local flame = Instance.new("Fire")
		flame.Size = 10
		flame.Parent = post

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 150, 50)
		light.Range = 15
		light.Brightness = 2
		light.Parent = post
	end

	-- Banners
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + math.pi/4
		local bannerPos = centerPos + Vector3.new(
			math.cos(angle) * (radius - 1 * s),
			12 * s,
			math.sin(angle) * (radius - 1 * s)
		)
		local banner = Instance.new("Part")
		banner.Size = Vector3.new(3 * s, 6 * s, 0.3 * s)
		banner.Color = Color3.fromRGB(180, 40, 40)
		banner.Material = Enum.Material.Fabric
		banner.Anchored = true
		banner.Position = bannerPos
		banner.Orientation = Vector3.new(0, -math.deg(angle) + 90, 0)
		banner.Parent = model
	end

	model.PrimaryPart = floor
	return model
end

-- // Fishing ----------------------------------------------------------------------------
-- Build a fishing dock/pier spot.
function VisualEffects.BuildFishingSpot(): Model
	local model = Instance.new("Model")
	model.Name = "FishingSpot"

	-- Dock planks (wider)
	for i = 1, 6 do
		local plank = Instance.new("Part")
		plank.Size = Vector3.new(4, 0.4, 1.2)
		plank.Color = Color3.fromRGB(110, 75, 40)
		plank.Material = Enum.Material.WoodPlanks
		plank.Anchored = true
		plank.Position = Vector3.new(0, 1, (i - 3.5) * 1.3)
		plank.Parent = model
	end

	-- Support posts
	for _, x in ipairs({ -1.7, 1.7 }) do
		for _, z in ipairs({ -3.5, 3.5 }) do
			local post = Instance.new("Part")
			post.Size = Vector3.new(0.6, 4, 0.6)
			post.Color = Color3.fromRGB(80, 55, 30)
			post.Material = Enum.Material.Wood
			post.Anchored = true
			post.Position = Vector3.new(x, 0, z)
			post.Parent = model
		end
	end

	-- Railings (back and sides, open front for casting)
	for _, x in ipairs({ -1.8, 1.8 }) do
		-- Side rails
		local rail = Instance.new("Part")
		rail.Size = Vector3.new(0.25, 0.25, 7)
		rail.Color = Color3.fromRGB(90, 60, 35)
		rail.Material = Enum.Material.Wood
		rail.Anchored = true
		rail.Position = Vector3.new(x, 2.5, 0)
		rail.Parent = model
		-- Rail posts
		for _, z in ipairs({ -3, 0, 3 }) do
			local rpost = Instance.new("Part")
			rpost.Size = Vector3.new(0.25, 1.8, 0.25)
			rpost.Color = Color3.fromRGB(90, 60, 35)
			rpost.Anchored = true
			rpost.Position = Vector3.new(x, 1.8, z)
			rpost.Parent = model
		end
	end
	-- Back rail
	local backRail = Instance.new("Part")
	backRail.Size = Vector3.new(4, 0.25, 0.25)
	backRail.Color = Color3.fromRGB(90, 60, 35)
	backRail.Anchored = true
	backRail.Position = Vector3.new(0, 2.5, -3.5)
	backRail.Parent = model

	-- Lantern on post
	local lampPost = Instance.new("Part")
	lampPost.Size = Vector3.new(0.4, 4, 0.4)
	lampPost.Color = Color3.fromRGB(70, 70, 80)
	lampPost.Material = Enum.Material.Metal
	lampPost.Anchored = true
	lampPost.Position = Vector3.new(-1.8, 3, -3.2)
	lampPost.Parent = model

	local lamp = Instance.new("Part")
	lamp.Size = Vector3.new(0.8, 1, 0.8)
	lamp.Color = Color3.fromRGB(255, 200, 100)
	lamp.Material = Enum.Material.Neon
	lamp.Anchored = true
	lamp.Position = Vector3.new(-1.8, 5.2, -3.2)
	lamp.Parent = model

	local lampLight = Instance.new("PointLight")
	lampLight.Color = Color3.fromRGB(255, 190, 100)
	lampLight.Range = 12
	lampLight.Brightness = 1.5
	lampLight.Parent = lamp

	-- Bucket
	local bucket = Instance.new("Part")
	bucket.Size = Vector3.new(1, 1.2, 1)
	bucket.Shape = Enum.PartType.Cylinder
	bucket.Color = Color3.fromRGB(120, 120, 130)
	bucket.Material = Enum.Material.Metal
	bucket.Anchored = true
	bucket.Position = Vector3.new(1.2, 1.7, 2.5)
	bucket.Parent = model

	-- Crate with fish
	local crate = Instance.new("Part")
	crate.Size = Vector3.new(1.5, 1.5, 1.5)
	crate.Color = Color3.fromRGB(130, 90, 50)
	crate.Material = Enum.Material.WoodPlanks
	crate.Anchored = true
	crate.Position = Vector3.new(-1.2, 1.9, 2.8)
	crate.Parent = model

	-- Sign
	local sign = Instance.new("Part")
	sign.Name = "DockSign"
	sign.Size = Vector3.new(4, 2, 0.4)
	sign.Color = Color3.fromRGB(60, 40, 20)
	sign.Material = Enum.Material.Wood
	sign.Anchored = true
	sign.Position = Vector3.new(0, 4.5, -3.8)
	sign.Parent = model

	local signGui = Instance.new("SurfaceGui")
	signGui.Face = Enum.NormalId.Front
	signGui.Parent = sign
	local signLabel = Instance.new("TextLabel")
	signLabel.Size = UDim2.new(1, 0, 1, 0)
	signLabel.BackgroundTransparency = 1
	signLabel.Text = "CAST LINE HERE"
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true
	signLabel.TextColor3 = Color3.new(1, 1, 1)
	signLabel.TextStrokeTransparency = 0.5
	signLabel.Parent = signGui

	local castPad = Instance.new("Part")
	castPad.Name = "CastPad"
	castPad.Size = Vector3.new(4, 0.5, 7)
	castPad.Color = Color3.fromRGB(110, 75, 40)
	castPad.Material = Enum.Material.WoodPlanks
	castPad.Transparency = 1
	castPad.Anchored = true
	castPad.CanCollide = false
	castPad.Position = Vector3.new(0, 1.2, 0)
	castPad.Parent = model
	model.PrimaryPart = castPad

	-- Water (larger, animated waves)
	local water = Instance.new("Part")
	water.Name = "Water"
	water.Size = Vector3.new(20, 0.5, 16)
	water.Color = Color3.fromRGB(50, 130, 180)
	water.Material = Enum.Material.Water
	water.Transparency = 0.25
	water.Anchored = true
	water.CanCollide = false
	water.Position = Vector3.new(0, 0.2, 10)
	water.Parent = model

	-- Animated wave particles
	local waves = Instance.new("ParticleEmitter")
	waves.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	waves.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
	waves.Size = NumberSequence.new(0.5)
	waves.Transparency = NumberSequence.new(0.7)
	waves.Speed = NumberRange.new(1, 2)
	waves.Lifetime = NumberRange.new(2, 3)
	waves.Rate = 8
	waves.Parent = water

	return model
end

function VisualEffects.BuildFishingLandmark(): Model
	local model = Instance.new("Model")
	model.Name = "FishingLandmark"

	local post = Instance.new("Part")
	post.Name = "Post"
	post.Size = Vector3.new(1.4, 18, 1.4)
	post.Color = Color3.fromRGB(80, 55, 30)
	post.Material = Enum.Material.Wood
	post.Anchored = true
	post.Position = Vector3.new(0, 9, 0)
	post.Parent = model

	local board = Instance.new("Part")
	board.Name = "Board"
	board.Size = Vector3.new(28, 10, 1.2)
	board.Color = Color3.fromRGB(30, 90, 150)
	board.Material = Enum.Material.SmoothPlastic
	board.Anchored = true
	board.Position = Vector3.new(0, 16, 0)
	board.Parent = model

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "FISHING"
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	local guiBack = Instance.new("SurfaceGui")
	guiBack.Face = Enum.NormalId.Back
	guiBack.Parent = board
	local labelBack = Instance.new("TextLabel")
	labelBack.Size = UDim2.new(1, 0, 1, 0)
	labelBack.BackgroundTransparency = 1
	labelBack.Text = "FISHING"
	labelBack.Font = Enum.Font.GothamBlack
	labelBack.TextScaled = true
	labelBack.TextColor3 = Color3.fromRGB(255, 255, 255)
	labelBack.TextStrokeTransparency = 0.4
	labelBack.Parent = guiBack

	model.PrimaryPart = board
	return model
end

function VisualEffects.BuildChampionMonument(): Model
	local model = Instance.new("Model")
	model.Name = "ChampionBoard"

	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end

	local stone = Color3.fromRGB(55, 48, 42)
	local gold = Color3.fromRGB(255, 200, 70)
	local dark = Color3.fromRGB(28, 22, 16)

	local base = add("Base", Vector3.new(22, 2.2, 10), CFrame.new(0, 1.1, 0), stone, Enum.Material.Slate)
	add("Step", Vector3.new(18, 0.8, 8), CFrame.new(0, 2.4, 0), Color3.fromRGB(80, 70, 55), Enum.Material.Cobblestone)
	add("PillarL", Vector3.new(2.4, 28, 2.4), CFrame.new(-16, 16.4, 0), stone, Enum.Material.Marble)
	add("PillarR", Vector3.new(2.4, 28, 2.4), CFrame.new(16, 16.4, 0), stone, Enum.Material.Marble)
	add("CapL", Vector3.new(3.4, 1.4, 3.4), CFrame.new(-16, 31, 0), gold, Enum.Material.Metal)
	add("CapR", Vector3.new(3.4, 1.4, 3.4), CFrame.new(16, 31, 0), gold, Enum.Material.Metal)
	add("Lintel", Vector3.new(36, 2.2, 3.2), CFrame.new(0, 31.2, 0), stone, Enum.Material.Marble)
	local title = add("Title", Vector3.new(28, 4.2, 1.2), CFrame.new(0, 34.2, 0), dark, Enum.Material.SmoothPlastic)
	local screen = add("Board", Vector3.new(32, 22, 1.4), CFrame.new(0, 17, 0), dark, Enum.Material.SmoothPlastic)
	add("Trim", Vector3.new(33.2, 23.2, 0.6), CFrame.new(0, 17, -0.6), gold, Enum.Material.Metal)
	add("TrimBack", Vector3.new(33.2, 23.2, 0.6), CFrame.new(0, 17, 0.6), gold, Enum.Material.Metal)
	local lamp = add("Lamp", Vector3.new(1.6, 1.6, 1.6), CFrame.new(0, 37.2, 0), gold, Enum.Material.Neon, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = gold
	light.Brightness = 3
	light.Range = 40
	light.Parent = lamp

	local function face(part: BasePart, side: Enum.NormalId, name: string, text: string, size: number): TextLabel
		local gui = Instance.new("SurfaceGui")
		gui.Name = name
		gui.Face = side
		gui.PixelsPerStud = 22
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Name = "RankText"
		label.Size = UDim2.new(1, -24, 1, -24)
		label.Position = UDim2.new(0, 12, 0, 12)
		label.BackgroundTransparency = 1
		label.Text = text
		label.Font = Enum.Font.GothamBold
		label.TextSize = size
		label.TextColor3 = Color3.fromRGB(255, 220, 120)
		label.TextStrokeTransparency = 0.35
		label.TextWrapped = true
		label.TextYAlignment = Enum.TextYAlignment.Top
		label.Parent = gui
		return label
	end
	face(title, Enum.NormalId.Front, "TitleFront", "ARENA CHAMPIONS", 48)
	face(title, Enum.NormalId.Back, "TitleBack", "ARENA CHAMPIONS", 48)
	local front = face(screen, Enum.NormalId.Front, "BoardFront", "Win battles to claim a name.", 32)
	local back = face(screen, Enum.NormalId.Back, "BoardBack", "Win battles to claim a name.", 32)
	front:SetAttribute("ChampionText", true)
	back:SetAttribute("ChampionText", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "BoardPrompt"
	prompt.ActionText = "Read Champions"
	prompt.ObjectText = "Leaderboard"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 32
	prompt.RequiresLineOfSight = false
	prompt.Parent = screen

	model.PrimaryPart = base
	return model
end

function VisualEffects.BuildFusionMachine(): Model
	local model = Instance.new("Model")
	model.Name = "FusionLab"

	local function add(name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.Anchored = true
		if shape then
			p.Shape = shape
		end
		p.Parent = model
		return p
	end

	local metal = Color3.fromRGB(48, 48, 62)
	local dark = Color3.fromRGB(28, 24, 40)
	local neon = Color3.fromRGB(170, 80, 255)
	local gold = Color3.fromRGB(255, 200, 80)

	local base = add("Base", Vector3.new(16, 1.2, 16), CFrame.new(0, 0.6, 0), dark, Enum.Material.Metal)
	add("Ring", Vector3.new(14, 0.5, 14), CFrame.new(0, 1.2, 0), metal, Enum.Material.DiamondPlate)
	add("Step", Vector3.new(10, 0.4, 10), CFrame.new(0, 1.5, 0), Color3.fromRGB(70, 55, 100), Enum.Material.SmoothPlastic)

	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local x, z = math.cos(a) * 6.2, math.sin(a) * 6.2
		add("Pylon" .. i, Vector3.new(1.4, 9, 1.4), CFrame.new(x, 5.7, z), metal, Enum.Material.Metal)
		add("PylonGlow" .. i, Vector3.new(0.35, 7, 0.35), CFrame.new(x, 5.7, z), neon, Enum.Material.Neon)
	end

	local chamber = add("Chamber", Vector3.new(8, 6.5, 6.5), CFrame.new(0, 5.6, 0) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(140, 90, 220), Enum.Material.ForceField, Enum.PartType.Cylinder)
	chamber.Transparency = 0.35
	chamber.CanCollide = false

	local core = add("Core", Vector3.new(3.2, 3.2, 3.2), CFrame.new(0, 5.6, 0), neon, Enum.Material.Neon, Enum.PartType.Ball)
	core.CanCollide = false
	local light = Instance.new("PointLight")
	light.Color = neon
	light.Brightness = 3
	light.Range = 22
	light.Parent = core
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new(neon, Color3.fromRGB(255, 180, 255))
	sparks.Size = NumberSequence.new(0.25, 0.05)
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Rate = 18
	sparks.Speed = NumberRange.new(1, 3)
	sparks.Parent = core

	add("Cap", Vector3.new(7, 1.2, 7), CFrame.new(0, 10.1, 0), metal, Enum.Material.Metal)
	add("Crown", Vector3.new(2.4, 2.2, 2.4), CFrame.new(0, 11.4, 0), gold, Enum.Material.Neon, Enum.PartType.Ball)

	for i = 1, 3 do
		local a = (i / 3) * math.pi * 2
		local x, z = math.cos(a) * 5.4, math.sin(a) * 5.4
		add("Pod" .. i, Vector3.new(2.4, 1.6, 2.4), CFrame.new(x, 2.5, z), Color3.fromRGB(90, 70, 130), Enum.Material.SmoothPlastic)
		add("PodGlow" .. i, Vector3.new(1.4, 0.4, 1.4), CFrame.new(x, 3.4, z), neon, Enum.Material.Neon)
		add("Pipe" .. i, Vector3.new(0.5, 0.5, 4.2), CFrame.new(x * 0.5, 3.8, z * 0.5) * CFrame.lookAt(Vector3.new(x * 0.5, 3.8, z * 0.5), Vector3.new(0, 5.2, 0)), metal, Enum.Material.Metal)
	end

	local console = add("Console", Vector3.new(5.5, 2.2, 2.4), CFrame.new(0, 2.4, 7.2), Color3.fromRGB(40, 35, 55), Enum.Material.SmoothPlastic)
	add("Screen", Vector3.new(4.2, 1.4, 0.2), CFrame.new(0, 3.4, 8.35), neon, Enum.Material.Neon)

	local sign = add("Sign", Vector3.new(14, 4.2, 0.7), CFrame.new(0, 14.2, 0), Color3.fromRGB(40, 20, 60), Enum.Material.SmoothPlastic)
	local function face(part: BasePart, face: Enum.NormalId, text: string)
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(1, 0, 1, 0)
		label.BackgroundTransparency = 1
		label.Text = text
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 230, 255)
		label.TextStrokeTransparency = 0.4
		label.Parent = gui
	end
	face(sign, Enum.NormalId.Front, "FUSION LAB")
	face(sign, Enum.NormalId.Back, "FUSION LAB")
	face(console, Enum.NormalId.Top, "3 COPIES + PLOT WORK MATS")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "FusionPrompt"
	prompt.ActionText = "Open Fusion Lab"
	prompt.ObjectText = "Fusion Reactor"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = console

	model.PrimaryPart = base
	return model
end

local function kioskPart(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function kioskLabel(part: BasePart, face: Enum.NormalId, text: string, color: Color3?)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui
end

local function kioskBeacon(parent: BasePart, text: string, color: Color3)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "KioskBeacon"
	billboard.Size = UDim2.new(7, 0, 1.4, 0)
	billboard.StudsOffset = Vector3.new(0, 3.2, 0)
	billboard.MaxDistance = 90
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0.2
	billboard.Parent = parent
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.35
	label.Parent = billboard
end

function VisualEffects.BuildQuestKiosk(): Model
	local model = Instance.new("Model")
	model.Name = "QuestBoard"

	local wood = Color3.fromRGB(128, 88, 48)
	local dark = Color3.fromRGB(62, 40, 22)
	local cork = Color3.fromRGB(196, 148, 86)
	local paper = Color3.fromRGB(245, 235, 210)
	local gold = Color3.fromRGB(255, 200, 80)

	local base = kioskPart(model, "Base", Vector3.new(12, 0.7, 8), CFrame.new(0, 0.35, 0), dark, Enum.Material.WoodPlanks)
	kioskPart(model, "Step", Vector3.new(8, 0.4, 3.2), CFrame.new(0, 0.85, 3.2), Color3.fromRGB(90, 65, 40), Enum.Material.Cobblestone)
	kioskPart(model, "PostL", Vector3.new(1.1, 11, 1.1), CFrame.new(-4.6, 6.1, -2.2), wood, Enum.Material.Wood)
	kioskPart(model, "PostR", Vector3.new(1.1, 11, 1.1), CFrame.new(4.6, 6.1, -2.2), wood, Enum.Material.Wood)
	kioskPart(model, "CapL", Vector3.new(1.6, 0.7, 1.6), CFrame.new(-4.6, 11.8, -2.2), gold, Enum.Material.Metal)
	kioskPart(model, "CapR", Vector3.new(1.6, 0.7, 1.6), CFrame.new(4.6, 11.8, -2.2), gold, Enum.Material.Metal)
	kioskPart(model, "Roof", Vector3.new(13, 0.7, 8), CFrame.new(0, 12.2, -0.4) * CFrame.Angles(-0.16, 0, 0), Color3.fromRGB(150, 55, 45), Enum.Material.Wood)
	kioskPart(model, "RoofTrim", Vector3.new(13.6, 0.25, 8.4), CFrame.new(0, 12.55, -0.4) * CFrame.Angles(-0.16, 0, 0), gold, Enum.Material.Metal)
	local board = kioskPart(model, "Board", Vector3.new(9.4, 6.4, 0.6), CFrame.new(0, 6.4, -2.2), cork, Enum.Material.Wood)
	kioskPart(model, "Frame", Vector3.new(10.2, 7.2, 0.35), CFrame.new(0, 6.4, -2.5), wood, Enum.Material.Wood)
	for i = 0, 3 do
		kioskPart(model, "Note" .. i, Vector3.new(1.8, 2.3, 0.1), CFrame.new(-3.2 + i * 2.15, 6.8, -1.85), paper, Enum.Material.Cardboard)
	end
	kioskPart(model, "Ribbon", Vector3.new(9, 0.35, 0.12), CFrame.new(0, 9.2, -1.85), Color3.fromRGB(200, 50, 50), Enum.Material.Fabric)
	local lamp = kioskPart(model, "Lantern", Vector3.new(1.2, 1.2, 1.2), CFrame.new(0, 13.4, 0), gold, Enum.Material.Neon, Enum.PartType.Ball)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 190, 80)
	light.Brightness = 2.2
	light.Range = 22
	light.Parent = lamp
	kioskPart(model, "Chest", Vector3.new(2.8, 1.8, 2), CFrame.new(-3.4, 1.55, 2.2), Color3.fromRGB(150, 110, 40), Enum.Material.Wood)
	kioskPart(model, "Scroll", Vector3.new(1.6, 0.2, 2.4), CFrame.new(3.2, 1.15, 2), paper, Enum.Material.Cardboard)
	local sign = kioskPart(model, "Sign", Vector3.new(10, 2.4, 0.5), CFrame.new(0, 11.1, -1.4), Color3.fromRGB(40, 24, 14), Enum.Material.Wood)
	kioskLabel(sign, Enum.NormalId.Front, "QUEST BOARD")
	kioskLabel(sign, Enum.NormalId.Back, "QUEST BOARD")
	kioskLabel(board, Enum.NormalId.Front, "DAILY TASKS\nTOUCH THE ORBS", Color3.fromRGB(70, 42, 18))
	kioskBeacon(sign, "QUESTS", Color3.fromRGB(255, 220, 120))

	model.PrimaryPart = base
	return model
end

function VisualEffects.BuildExpeditionKiosk(): Model
	local model = Instance.new("Model")
	model.Name = "ExpeditionBoard"

	local wood = Color3.fromRGB(108, 74, 40)
	local canvas = Color3.fromRGB(28, 130, 78)
	local map = Color3.fromRGB(214, 188, 128)
	local gold = Color3.fromRGB(255, 210, 80)

	local base = kioskPart(model, "Base", Vector3.new(12, 0.7, 9), CFrame.new(0, 0.35, 0), Color3.fromRGB(70, 55, 35), Enum.Material.WoodPlanks)
	kioskPart(model, "Rug", Vector3.new(7, 0.12, 5), CFrame.new(0, 0.76, 2), Color3.fromRGB(40, 90, 55), Enum.Material.Fabric)
	kioskPart(model, "Desk", Vector3.new(8, 1.6, 3.6), CFrame.new(0, 1.5, 1.6), wood, Enum.Material.Wood)
	kioskPart(model, "Map", Vector3.new(5.4, 0.1, 2.8), CFrame.new(0, 2.35, 1.5), map, Enum.Material.Cardboard)
	kioskPart(model, "PoleL", Vector3.new(0.7, 11, 0.7), CFrame.new(-5, 5.9, -2.6), wood, Enum.Material.Wood)
	kioskPart(model, "PoleR", Vector3.new(0.7, 11, 0.7), CFrame.new(5, 5.9, -2.6), wood, Enum.Material.Wood)
	kioskPart(model, "PoleF", Vector3.new(0.55, 9, 0.55), CFrame.new(0, 5, 3.4), wood, Enum.Material.Wood)
	kioskPart(model, "Canopy", Vector3.new(12.4, 0.35, 9), CFrame.new(0, 11.4, 0.2) * CFrame.Angles(-0.1, 0, 0), canvas, Enum.Material.Fabric)
	kioskPart(model, "CanopyTrim", Vector3.new(12.8, 0.2, 9.4), CFrame.new(0, 11.65, 0.2) * CFrame.Angles(-0.1, 0, 0), gold, Enum.Material.Metal)
	kioskPart(model, "Pack", Vector3.new(2.2, 2.6, 1.7), CFrame.new(-3.6, 2.5, -1.4), Color3.fromRGB(90, 70, 40), Enum.Material.Fabric)
	kioskPart(model, "Crate", Vector3.new(2.4, 1.8, 2.2), CFrame.new(3.8, 1.6, -1.2), Color3.fromRGB(130, 95, 55), Enum.Material.WoodPlanks)
	kioskPart(model, "Compass", Vector3.new(1.3, 0.28, 1.3), CFrame.new(2.2, 2.5, 1.8), gold, Enum.Material.Metal, Enum.PartType.Cylinder)
	kioskPart(model, "Scope", Vector3.new(2.1, 0.4, 0.4), CFrame.new(2.8, 2.8, 0.7), Color3.fromRGB(50, 50, 55), Enum.Material.Metal, Enum.PartType.Cylinder)
	local button = kioskPart(model, "ExpeditionButton", Vector3.new(2, 2, 2), CFrame.new(0, 3.5, 1.7), Color3.fromRGB(70, 255, 110), Enum.Material.Neon, Enum.PartType.Ball)
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(80, 255, 120)
	glow.Brightness = 3
	glow.Range = 16
	glow.Parent = button
	local board = kioskPart(model, "Board", Vector3.new(8.4, 4.4, 0.5), CFrame.new(0, 6.6, -2.6), Color3.fromRGB(28, 78, 42), Enum.Material.Wood)
	kioskLabel(board, Enum.NormalId.Front, "EXPEDITIONS\nSEND A TEAM")
	kioskLabel(board, Enum.NormalId.Back, "EXPEDITIONS")
	local sign = kioskPart(model, "Sign", Vector3.new(10, 2.2, 0.45), CFrame.new(0, 10.2, -1.6), Color3.fromRGB(18, 48, 28), Enum.Material.Wood)
	kioskLabel(sign, Enum.NormalId.Front, "ADVENTURE")
	kioskLabel(sign, Enum.NormalId.Back, "ADVENTURE")
	kioskBeacon(sign, "EXPEDITIONS", Color3.fromRGB(120, 255, 150))

	model.PrimaryPart = base
	return model
end

function VisualEffects.BuildLegendaryRushFX(): Folder
	local folder = Instance.new("Folder")
	folder.Name = "LegendaryRushFX"
	local center = Vector3.new(127, 80, 98)
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local ring = Instance.new("Part")
		ring.Name = "Aurora" .. i
		ring.Shape = Enum.PartType.Ball
		ring.Size = Vector3.new(18, 18, 18)
		ring.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * 90, 20 + (i % 2) * 12, math.sin(angle) * 90))
		ring.Anchored = true
		ring.CanCollide = false
		ring.Material = Enum.Material.Neon
		ring.Color = if i % 2 == 0 then Color3.fromRGB(255, 160, 40) else Color3.fromRGB(180, 70, 255)
		ring.Transparency = 0.25
		ring.Parent = folder
		local light = Instance.new("PointLight")
		light.Color = ring.Color
		light.Brightness = 4
		light.Range = 70
		light.Parent = ring
		local pe = Instance.new("ParticleEmitter")
		pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		pe.Rate = 12
		pe.Lifetime = NumberRange.new(1.4, 2.4)
		pe.Speed = NumberRange.new(2, 6)
		pe.SpreadAngle = Vector2.new(40, 40)
		pe.Color = ColorSequence.new(ring.Color)
		pe.Parent = ring
	end
	return folder
end

-- Cast animation: rod appears in hand, bobber flies out with a visible line.
-- Returns { Bobber, Rod, Line } for bite/catch animation.
function VisualEffects.CastBobber(player: Player, fromPos: Vector3, toPos: Vector3): any
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")

	-- Fishing rod (held diagonally)
	local rod = Instance.new("Part")
	rod.Name = "FishingRod"
	rod.Size = Vector3.new(0.25, 7, 0.25)
	rod.Color = Color3.fromRGB(110, 75, 40)
	rod.Material = Enum.Material.Wood
	rod.Anchored = true
	rod.CanCollide = false
	rod.Parent = workspace

	-- Rod handle (grip)
	local grip = Instance.new("Part")
	grip.Size = Vector3.new(0.35, 1.5, 0.35)
	grip.Color = Color3.fromRGB(60, 40, 25)
	grip.Material = Enum.Material.Wood
	grip.Anchored = true
	grip.CanCollide = false
	grip.Parent = rod

	-- Reel
	local reel = Instance.new("Part")
	reel.Size = Vector3.new(0.6, 0.6, 0.4)
	reel.Shape = Enum.PartType.Cylinder
	reel.Color = Color3.fromRGB(180, 180, 190)
	reel.Material = Enum.Material.Metal
	reel.Anchored = true
	reel.CanCollide = false
	reel.Parent = rod

	-- Position rod in player's hand area (diagonal)
	if hrp then
		local hrpPos = (hrp :: BasePart).Position
		local lookDir = (hrp :: BasePart).CFrame.LookVector
		local rodBase = hrpPos + Vector3.new(0, 2, 0) + lookDir * 1.5
		-- Angle toward cast direction
		local toDir = (toPos - rodBase).Unit
		rod.CFrame = CFrame.new(rodBase + Vector3.new(0, 2, 0), rodBase + toDir * 5 + Vector3.new(0, 3, 0))
		-- Grip at base
		grip.CFrame = rod.CFrame * CFrame.new(0, -2.8, 0)
		reel.CFrame = rod.CFrame * CFrame.new(0.3, -2, 0)
	end
	local rodTip = rod.CFrame * CFrame.new(0, 3.5, 0)

	-- Detailed bobber: striped with glow tip
	local bobber = Instance.new("Part")
	bobber.Name = "Bobber"
	bobber.Size = Vector3.new(0.9, 1.4, 0.9)
	bobber.Shape = Enum.PartType.Ball
	bobber.Color = Color3.fromRGB(255, 60, 60)
	bobber.Anchored = true
	bobber.CanCollide = false
	bobber.Position = fromPos
	bobber.Parent = workspace

	-- White stripe
	local stripe = Instance.new("Part")
	stripe.Size = Vector3.new(0.95, 0.45, 0.95)
	stripe.Shape = Enum.PartType.Ball
	stripe.Color = Color3.fromRGB(255, 255, 255)
	stripe.Anchored = true
	stripe.CanCollide = false
	stripe.Parent = bobber

	-- Glow tip (for night visibility)
	local tipLight = Instance.new("PointLight")
	tipLight.Color = Color3.fromRGB(255, 100, 100)
	tipLight.Range = 6
	tipLight.Brightness = 1.5
	tipLight.Parent = bobber

	-- Fishing line (Beam from rod tip to bobber)
	local line = Instance.new("Beam")
	line.Color = ColorSequence.new(Color3.fromRGB(220, 220, 220))
	line.Transparency = NumberSequence.new(0.2)
	line.Width0 = 0.05
	line.Width1 = 0.05
	-- Attachments
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 3.5, 0)
	att0.Parent = rod
	local att1 = Instance.new("Attachment")
	att1.Parent = bobber
	line.Attachment0 = att0
	line.Attachment1 = att1
	line.Parent = rod

	-- Animate arc
	task.spawn(function()
		local steps = 20
		for i = 1, steps do
			if not bobber or not bobber.Parent then break end
			local t = i / steps
			local pos = fromPos:Lerp(toPos, t)
			pos += Vector3.new(0, math.sin(t * math.pi) * 8, 0)
			bobber.Position = pos
			stripe.Position = pos
			task.wait(0.05)
		end
		VisualEffects.PlaySplash(toPos)
	end)

	return { Bobber = bobber, Rod = rod, Line = line, Stripe = stripe }
end

function VisualEffects.ClearFishingGear(gear: any)
	if type(gear) ~= "table" then
		return
	end
	for _, key in ipairs({ "Rod", "Bobber", "Stripe", "Line" }) do
		local inst = gear[key]
		if inst and inst.Parent then
			inst:Destroy()
		end
	end
end

-- Bite animation: bobber dips and shakes.
function VisualEffects.PlayBite(bobber: BasePart)
	task.spawn(function()
		for i = 1, 10 do
			if not bobber or not bobber.Parent then break end
			bobber.Position += Vector3.new(0, -0.3, 0)
			task.wait(0.1)
			if not bobber or not bobber.Parent then break end
			bobber.Position += Vector3.new(
				(math.random() - 0.5) * 0.5,
				0.3,
				(math.random() - 0.5) * 0.5
			)
			task.wait(0.1)
		end
	end)
	-- "!" indicator
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 60, 0, 60)
	billboard.AlwaysOnTop = true
	billboard.Parent = bobber
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = "❗"
	label.Font = Enum.Font.GothamBold
	label.TextSize = 48
	label.TextColor3 = Color3.fromRGB(255, 220, 50)
	label.TextStrokeTransparency = 0.3
	label.Parent = billboard
end

-- Splash particles.
function VisualEffects.PlaySplash(pos: Vector3)
	local splash = Instance.new("ParticleEmitter")
	splash.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	splash.Color = ColorSequence.new(Color3.fromRGB(150, 210, 255))
	splash.Size = NumberSequence.new(0.6)
	splash.Speed = NumberRange.new(8, 15)
	splash.Lifetime = NumberRange.new(0.4, 0.8)
	splash.Rate = 50
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Position = pos
	anchor.Parent = workspace
	splash.Parent = anchor
	task.delay(0.5, function()
		if anchor and anchor.Parent then anchor:Destroy() end
	end)
	-- Ripple ring
	local ripple = Instance.new("Part")
	ripple.Size = Vector3.new(3, 0.2, 3)
	ripple.Shape = Enum.PartType.Cylinder
	ripple.Color = Color3.fromRGB(150, 210, 255)
	ripple.Transparency = 0.5
	ripple.Anchored = true
	ripple.CanCollide = false
	ripple.Position = pos
	ripple.Parent = workspace
	local tween = game:GetService("TweenService"):Create(ripple,
		TweenInfo.new(1),
		{ Size = Vector3.new(8, 0.2, 8), Transparency = 1 }
	)
	tween:Play()
	task.delay(1.2, function()
		if ripple and ripple.Parent then ripple:Destroy() end
	end)
end

-- Catch animation: reward flies up with sparkles.
function VisualEffects.PlayCatch(pos: Vector3, rewardKind: string)
	VisualEffects.PlaySplash(pos)
	-- Sparkle burst
	local burst = Instance.new("ParticleEmitter")
	burst.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	local color = Color3.fromRGB(255, 220, 100)
	if rewardKind == "Brainrot" then
		color = Color3.fromRGB(255, 150, 255)
	elseif rewardKind == "Material" then
		color = Color3.fromRGB(150, 200, 255)
	end
	burst.Color = ColorSequence.new(color)
	burst.Size = NumberSequence.new(1)
	burst.Speed = NumberRange.new(10, 20)
	burst.Lifetime = NumberRange.new(0.6, 1)
	burst.Rate = 80
	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Position = pos + Vector3.new(0, 2, 0)
	anchor.Parent = workspace
	burst.Parent = anchor
	task.delay(0.8, function()
		if anchor and anchor.Parent then anchor:Destroy() end
	end)
end

-- Build a 3D fish model for catch visualization.
-- golden=true for brainrot catches (special gold fish).
function VisualEffects.BuildFish(golden: boolean): Model

	local color = golden and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(100, 150, 200)

	-- Body
	local body = Instance.new("Part")
	body.Size = Vector3.new(1.2, 0.8, 2.5)
	body.Shape = Enum.PartType.Ball
	body.Color = color
	body.Material = if golden then Enum.Material.Metal else Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.Parent = model

	-- Tail
	local tail = Instance.new("Part")
	tail.Size = Vector3.new(0.2, 1, 1)
	tail.Color = color
	tail.Anchored = true
	tail.CanCollide = false
	tail.Position = body.Position - Vector3.new(0, 0, 1.5)
	tail.Rotation = Vector3.new(0, 0, 30)
	tail.Parent = model

	-- Dorsal fin
	local fin = Instance.new("Part")
	fin.Size = Vector3.new(0.2, 0.8, 1)
	fin.Color = color
	fin.Anchored = true
	fin.CanCollide = false
	fin.Position = body.Position + Vector3.new(0, 0.6, 0)
	fin.Parent = model

	-- Eyes
	for _, x in ipairs({ -0.3, 0.3 }) do
		local eye = Instance.new("Part")
		eye.Size = Vector3.new(0.25, 0.25, 0.2)
		eye.Shape = Enum.PartType.Ball
		eye.Color = Color3.fromRGB(20, 20, 20)
		eye.Anchored = true
		eye.CanCollide = false
		eye.Position = body.Position + Vector3.new(x, 0.2, 1.1)
		eye.Parent = model
	end

	if golden then
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = Color3.fromRGB(255, 220, 120)
		sparkles.Parent = body
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 200, 80)
		light.Range = 8
		light.Brightness = 1.5
		light.Parent = body
	end

	model.PrimaryPart = body
	return model
end

-- // Wandering Brainrots -----------------------------------------------------------------------
-- Add rarity aura to a wild brainrot model.
function VisualEffects.AddWildAura(model: Model, rarity: string, displayName: string?)
	local color = BrainrotData.RARITY_COLORS[rarity] or Color3.fromRGB(160, 160, 160)
	local primary = model.PrimaryPart
	if not primary then return end

	-- Glow light
	local light = Instance.new("PointLight")
	light.Name = "WildAura"
	light.Color = color
	light.Range = if rarity == "Legendary" then 15 else 8
	light.Brightness = if rarity == "Common" then 0.5 else 1.5
	light.Parent = primary

	-- Particles for Rare+
	if rarity ~= "Common" then
		local particles = Instance.new("ParticleEmitter")
		particles.Name = "WildSparkles"
		particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		particles.Color = ColorSequence.new(color)
		particles.Size = NumberSequence.new(0.6)
		particles.Speed = NumberRange.new(2, 4)
		particles.Lifetime = NumberRange.new(1, 1.5)
		particles.Rate = if rarity == "Legendary" then 30 else 10
		particles.Parent = primary
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WildTag"
	billboard.Size = UDim2.new(0, 110, 0, 36)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 220
	billboard.Adornee = primary
	billboard.Parent = model

	local function sitWildTag()
		if not (model.Parent and primary.Parent) then
			return
		end
		local ok, bbCF, bbSize = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and bbCF and bbSize and bbSize.Y >= 8 then
			local topY = (bbCF :: CFrame).Position.Y + (bbSize :: Vector3).Y * 0.5
			billboard.StudsOffsetWorldSpace = Vector3.new(0, (topY - primary.Position.Y) + 3, 0)
		else
			billboard.StudsOffsetWorldSpace = Vector3.new()
			billboard.StudsOffset = Vector3.new(0, 16, 0)
		end
	end
	sitWildTag()
	task.defer(sitWildTag)
	task.delay(0.4, sitWildTag)
	task.delay(1.5, sitWildTag)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = displayName or "???"
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.15
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = billboard

	local rarityPill = Instance.new("TextLabel")
	rarityPill.Size = UDim2.new(0, 64, 0, 14)
	rarityPill.Position = UDim2.new(0.5, -32, 0, 17)
	rarityPill.BackgroundColor3 = color
	rarityPill.BackgroundTransparency = 0.25
	rarityPill.Text = rarity
	rarityPill.Font = Enum.Font.GothamBold
	rarityPill.TextSize = 10
	rarityPill.TextColor3 = Color3.new(1, 1, 1)
	rarityPill.TextStrokeTransparency = 0.4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 7)
	corner.Parent = rarityPill
	rarityPill.Parent = billboard
end

-- Legendary beam: tall light pillar visible across the map.
-- Returns the beam model (destroy when caught/despawned).
function VisualEffects.BuildLegendaryBeam(pos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "LegendaryBeam"

	-- Main beam
	local beam = Instance.new("Part")
	beam.Size = Vector3.new(4, 200, 4)
	beam.Color = Color3.fromRGB(255, 150, 0)
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.4
	beam.Anchored = true
	beam.CanCollide = false
	beam.Position = pos + Vector3.new(0, 100, 0)
	beam.Parent = model

	-- Outer glow
	local glow = Instance.new("Part")
	glow.Size = Vector3.new(8, 200, 8)
	glow.Color = Color3.fromRGB(255, 200, 100)
	glow.Material = Enum.Material.Neon
	glow.Transparency = 0.7
	glow.Anchored = true
	glow.CanCollide = false
	glow.Position = pos + Vector3.new(0, 100, 0)
	glow.Parent = model

	-- Base ring
	local ring = Instance.new("Part")
	ring.Size = Vector3.new(12, 1, 12)
	ring.Shape = Enum.PartType.Cylinder
	ring.Color = Color3.fromRGB(255, 150, 0)
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.3
	ring.Anchored = true
	ring.CanCollide = false
	ring.Position = pos + Vector3.new(0, 1, 0)
	ring.Parent = model

	-- Rising particles
	local particles = Instance.new("ParticleEmitter")
	particles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	particles.Color = ColorSequence.new(Color3.fromRGB(255, 180, 60))
	particles.Size = NumberSequence.new(1.2)
	particles.Speed = NumberRange.new(15, 25)
	particles.Lifetime = NumberRange.new(1.5, 2.5)
	particles.Rate = 40
	particles.Parent = beam

	-- Light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 150, 0)
	light.Range = 30
	light.Brightness = 3
	light.Parent = beam

	-- Pulse animation
	task.spawn(function()
		while beam and beam.Parent do
			local t = os.clock()
			local scale = 1 + math.sin(t * 3) * 0.15
			beam.Size = Vector3.new(4 * scale, 200, 4 * scale)
			task.wait(0.05)
		end
	end)

	return model
end

-- Catch effect: poof + sparkles at catch position.
function VisualEffects.PlayWildCatch(pos: Vector3, rarity: string)
	local color = BrainrotData.RARITY_COLORS[rarity] or Color3.fromRGB(200, 200, 200)

	-- Poof
	local poof = Instance.new("ParticleEmitter")
	poof.Texture = "rbxasset://textures/particles/smoke_main.dds"
	poof.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
	poof.Size = NumberSequence.new(2)
	poof.Speed = NumberRange.new(5, 10)
	poof.Lifetime = NumberRange.new(0.5, 0.8)
	poof.Rate = 30

	-- Sparkles
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(color)
	sparkles.Size = NumberSequence.new(1)
	sparkles.Speed = NumberRange.new(10, 20)
	sparkles.Lifetime = NumberRange.new(0.8, 1.2)
	sparkles.Rate = 50

	local anchor = Instance.new("Part")
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Position = pos
	anchor.Parent = workspace
	poof.Parent = anchor
	sparkles.Parent = anchor

	task.delay(1, function()
		if anchor and anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- Zone discovery burst: colored sparkles when a player discovers a zone portal.
function VisualEffects.PlayZoneDiscover(pos: Vector3, color: Color3)
	local sparkles = Instance.new("ParticleEmitter")
	sparkles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkles.Color = ColorSequence.new(color)
	sparkles.Size = NumberSequence.new(1.2)
	sparkles.Speed = NumberRange.new(8, 18)
	sparkles.Lifetime = NumberRange.new(0.8, 1.4)
	sparkles.Rate = 60
	sparkles.RotSpeed = NumberRange.new(-120, 120)

	local anchor = Instance.new("Part")
	anchor.Name = "DiscoverBurst"
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Position = pos
	anchor.Parent = workspace
	sparkles.Parent = anchor

	task.delay(1.2, function()
		if anchor and anchor.Parent then
			anchor:Destroy()
		end
	end)
end

-- Robux shop lives here so BrainrotSync updates this existing ModuleScript
-- (new files like ShopSystem.lua are not created in Studio).
function VisualEffects.SetupRobuxShop()
	local MarketplaceService = game:GetService("MarketplaceService")
	local Players = game:GetService("Players")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local RunService = game:GetService("RunService")
	local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
	local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
	local PlotSystem = require(script.Parent:WaitForChild("PlotSystem"))

	local function hint(player: Player, text: string)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local ev = remotes and remotes:FindFirstChild("ShowHint")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireClient(player, text)
		end
	end
	local function catalog(): { any }
		return BrainrotData.MONETIZED_SHOP or {}
	end
	local function defByPass(passId: number): any
		for _, item in ipairs(catalog()) do
			if (item.GamePassId or 0) == passId and passId > 0 then
				return item
			end
		end
		return nil
	end
	local function passIdOf(item: any): number
		local attr = workspace:GetAttribute("ShopPass_" .. tostring(item.Id))
		if type(attr) == "number" and attr > 0 then
			return attr
		end
		return tonumber(item.GamePassId) or 0
	end
	local function playerOwns(player: Player, item: any): boolean
		if PlayerData.OwnsShopItem(player, item.Id) then
			return true
		end
		local passId = passIdOf(item)
		if passId > 0 then
			local ok, owned = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, passId)
			end)
			if ok and owned then
				PlayerData.GrantShopItem(player, item.Id)
				return true
			end
		end
		return false
	end
	local function weld(a: BasePart, b: BasePart)
		local w = Instance.new("WeldConstraint")
		w.Part0 = a
		w.Part1 = b
		w.Parent = b
	end
	local function addPart(model: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, shape: Enum.PartType?): BasePart
		local p: BasePart
		if shape == Enum.PartType.Ball or shape == Enum.PartType.Cylinder then
			local q = Instance.new("Part")
			q.Shape = shape :: Enum.PartType
			p = q
		elseif name == "Wedge" then
			p = Instance.new("WedgePart")
		else
			p = Instance.new("Part")
		end
		p.Name = name
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = mat
		p.CanCollide = false
		p.Massless = true
		p.Anchored = true
		p.Parent = model
		return p
	end
	local function finishModel(model: Model, root: BasePart)
		model.PrimaryPart = root
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= root then
				d.Anchored = false
				weld(root, d)
			end
		end
		root.Anchored = false
	end
	local function buildItemModel(itemId: string): Model
		local model = Instance.new("Model")
		model.Name = "ShopModel_" .. itemId
		local origin = CFrame.new()
		local root: BasePart
		if itemId == "skateboard" then
			root = addPart(model, "Deck", Vector3.new(3.1, 0.1, 0.9), origin, Color3.fromRGB(28, 26, 32), Enum.Material.SmoothPlastic)
			addPart(model, "Grip", Vector3.new(2.85, 0.04, 0.78), origin * CFrame.new(0, 0.07, 0), Color3.fromRGB(18, 18, 20), Enum.Material.Fabric)
			addPart(model, "Stripe", Vector3.new(2.4, 0.03, 0.18), origin * CFrame.new(0, 0.09, 0), Color3.fromRGB(255, 70, 90), Enum.Material.Neon)
			addPart(model, "Nose", Vector3.new(0.45, 0.1, 0.88), origin * CFrame.new(1.7, 0.12, 0) * CFrame.Angles(0, 0, math.rad(-18)), Color3.fromRGB(28, 26, 32), Enum.Material.SmoothPlastic)
			addPart(model, "Tail", Vector3.new(0.45, 0.1, 0.88), origin * CFrame.new(-1.7, 0.12, 0) * CFrame.Angles(0, 0, math.rad(18)), Color3.fromRGB(28, 26, 32), Enum.Material.SmoothPlastic)
			for _, x in ipairs({ -0.95, 0.95 }) do
				addPart(model, "Truck", Vector3.new(0.35, 0.16, 0.72), origin * CFrame.new(x, -0.14, 0), Color3.fromRGB(160, 165, 175), Enum.Material.Metal)
				for _, z in ipairs({ -0.28, 0.28 }) do
					addPart(model, "Wheel", Vector3.new(0.28, 0.34, 0.34), origin * CFrame.new(x, -0.32, z) * CFrame.Angles(0, 0, math.pi / 2), Color3.fromRGB(245, 90, 40), Enum.Material.SmoothPlastic, Enum.PartType.Cylinder)
				end
			end
		elseif itemId == "magic_carpet" then
			root = addPart(model, "Rug", Vector3.new(4.6, 0.12, 2.6), origin, Color3.fromRGB(165, 28, 58), Enum.Material.Fabric)
			addPart(model, "GoldTrim", Vector3.new(4.75, 0.08, 2.75), origin * CFrame.new(0, -0.02, 0), Color3.fromRGB(220, 175, 55), Enum.Material.Metal)
			addPart(model, "Medallion", Vector3.new(1.4, 0.06, 1.4), origin * CFrame.new(0, 0.08, 0), Color3.fromRGB(255, 210, 80), Enum.Material.Neon)
			addPart(model, "Inner", Vector3.new(3.4, 0.05, 1.6), origin * CFrame.new(0, 0.07, 0), Color3.fromRGB(95, 20, 110), Enum.Material.Fabric)
			for i = -2, 2 do
				addPart(model, "TasselF", Vector3.new(0.08, 0.55, 0.08), origin * CFrame.new(i * 0.85, -0.28, 1.4), Color3.fromRGB(220, 175, 55), Enum.Material.Fabric)
				addPart(model, "TasselB", Vector3.new(0.08, 0.55, 0.08), origin * CFrame.new(i * 0.85, -0.28, -1.4), Color3.fromRGB(220, 175, 55), Enum.Material.Fabric)
			end
		elseif itemId == "airplane" then
			root = addPart(model, "CabinCore", Vector3.new(1, 1, 1), origin, Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
			root.Transparency = 1
			addPart(model, "Floor", Vector3.new(9.5, 0.28, 3.6), origin * CFrame.new(0, -2.15, 0), Color3.fromRGB(70, 80, 95), Enum.Material.Metal)
			addPart(model, "Roof", Vector3.new(9.5, 0.22, 3.6), origin * CFrame.new(0, 2.25, 0), Color3.fromRGB(235, 238, 245), Enum.Material.SmoothPlastic)
			addPart(model, "WallL", Vector3.new(9.5, 4.2, 0.18), origin * CFrame.new(0, 0.05, -1.85), Color3.fromRGB(55, 105, 190), Enum.Material.SmoothPlastic)
			addPart(model, "WallR", Vector3.new(9.5, 4.2, 0.18), origin * CFrame.new(0, 0.05, 1.85), Color3.fromRGB(55, 105, 190), Enum.Material.SmoothPlastic)
			local glassL = addPart(model, "GlassL", Vector3.new(4.2, 1.6, 0.08), origin * CFrame.new(1.2, 0.7, -1.92), Color3.fromRGB(160, 220, 255), Enum.Material.Glass)
			glassL.Transparency = 0.45
			local glassR = addPart(model, "GlassR", Vector3.new(4.2, 1.6, 0.08), origin * CFrame.new(1.2, 0.7, 1.92), Color3.fromRGB(160, 220, 255), Enum.Material.Glass)
			glassR.Transparency = 0.45
			addPart(model, "Nose", Vector3.new(2.4, 2.4, 2.4), origin * CFrame.new(5.6, 0, 0), Color3.fromRGB(230, 70, 70), Enum.Material.SmoothPlastic, Enum.PartType.Ball)
			addPart(model, "Cowl", Vector3.new(1.6, 2.2, 2.2), origin * CFrame.new(4.4, 0, 0), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
			addPart(model, "TailBoom", Vector3.new(3.2, 1.1, 1.1), origin * CFrame.new(-6.0, 0.2, 0), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic)
			addPart(model, "TailFin", Vector3.new(1.4, 2.6, 0.16), origin * CFrame.new(-7.1, 1.6, 0), Color3.fromRGB(55, 105, 190), Enum.Material.SmoothPlastic)
			addPart(model, "TailWing", Vector3.new(1.1, 0.16, 3.4), origin * CFrame.new(-7.0, 0.35, 0), Color3.fromRGB(55, 105, 190), Enum.Material.SmoothPlastic)
			addPart(model, "Wing", Vector3.new(2.4, 0.22, 16), origin * CFrame.new(0.4, -0.6, 0), Color3.fromRGB(45, 90, 175), Enum.Material.SmoothPlastic)
			addPart(model, "Stripe", Vector3.new(9.2, 0.12, 0.35), origin * CFrame.new(0, -0.5, 0), Color3.fromRGB(255, 210, 70), Enum.Material.Neon)
			addPart(model, "Prop", Vector3.new(0.18, 3.6, 0.35), origin * CFrame.new(6.7, 0, 0), Color3.fromRGB(40, 40, 45), Enum.Material.Metal)
		elseif itemId == "sword" then
			root = addPart(model, "Handle", Vector3.new(0.22, 0.85, 0.22), origin * CFrame.new(0, -0.9, 0), Color3.fromRGB(70, 45, 28), Enum.Material.Wood)
			addPart(model, "Wrap", Vector3.new(0.24, 0.7, 0.24), origin * CFrame.new(0, -0.85, 0), Color3.fromRGB(120, 40, 40), Enum.Material.Fabric)
			addPart(model, "Pommel", Vector3.new(0.38, 0.38, 0.38), origin * CFrame.new(0, -1.4, 0), Color3.fromRGB(210, 175, 70), Enum.Material.Metal, Enum.PartType.Ball)
			addPart(model, "Guard", Vector3.new(0.9, 0.14, 0.22), origin * CFrame.new(0, -0.42, 0), Color3.fromRGB(210, 175, 70), Enum.Material.Metal)
			addPart(model, "Blade", Vector3.new(0.16, 2.7, 0.06), origin * CFrame.new(0, 0.95, 0), Color3.fromRGB(225, 230, 240), Enum.Material.Metal)
			addPart(model, "Fuller", Vector3.new(0.04, 2.3, 0.07), origin * CFrame.new(0, 0.9, 0), Color3.fromRGB(160, 170, 185), Enum.Material.Metal)
			addPart(model, "Tip", Vector3.new(0.14, 0.35, 0.05), origin * CFrame.new(0, 2.4, 0), Color3.fromRGB(240, 245, 255), Enum.Material.Metal)
		elseif itemId == "mace" then
			root = addPart(model, "Handle", Vector3.new(0.22, 2.15, 0.22), origin, Color3.fromRGB(75, 48, 28), Enum.Material.Wood)
			addPart(model, "Ring", Vector3.new(0.32, 0.12, 0.32), origin * CFrame.new(0, 0.95, 0), Color3.fromRGB(190, 155, 60), Enum.Material.Metal)
			addPart(model, "Head", Vector3.new(1.05, 1.05, 1.05), origin * CFrame.new(0, 1.45, 0), Color3.fromRGB(125, 128, 138), Enum.Material.Metal, Enum.PartType.Ball)
			for i = 0, 5 do
				local ang = i * math.pi / 3
				addPart(model, "Spike", Vector3.new(0.16, 0.55, 0.16), origin * CFrame.new(math.cos(ang) * 0.55, 1.45, math.sin(ang) * 0.55) * CFrame.Angles(0, 0, math.rad(55)), Color3.fromRGB(90, 92, 100), Enum.Material.Metal)
			end
			addPart(model, "TopSpike", Vector3.new(0.16, 0.5, 0.16), origin * CFrame.new(0, 2.05, 0), Color3.fromRGB(90, 92, 100), Enum.Material.Metal)
		else
			root = addPart(model, "Haft", Vector3.new(0.2, 2.3, 0.2), origin, Color3.fromRGB(92, 58, 32), Enum.Material.Wood)
			addPart(model, "Collar", Vector3.new(0.28, 0.16, 0.28), origin * CFrame.new(0, 0.85, 0), Color3.fromRGB(80, 82, 90), Enum.Material.Metal)
			addPart(model, "Bit", Vector3.new(1.35, 0.85, 0.12), origin * CFrame.new(0.45, 1.15, 0), Color3.fromRGB(150, 155, 165), Enum.Material.Metal)
			addPart(model, "Edge", Vector3.new(0.12, 0.95, 0.05), origin * CFrame.new(1.12, 1.15, 0), Color3.fromRGB(230, 235, 245), Enum.Material.Metal)
			addPart(model, "Poll", Vector3.new(0.35, 0.55, 0.22), origin * CFrame.new(-0.25, 1.15, 0), Color3.fromRGB(120, 124, 132), Enum.Material.Metal)
		end
		finishModel(model, root)
		return model
	end
	local function rideOffset(itemId: string): CFrame
		if itemId == "skateboard" then
			return CFrame.new(0, -3.15, 0)
		elseif itemId == "magic_carpet" then
			return CFrame.new(0, -3.05, 0)
		elseif itemId == "airplane" then
			return CFrame.new(0, 0.15, 0)
		end
		return CFrame.new()
	end
	local function attachRide(char: Model, itemId: string)
		local old = char:FindFirstChild("ShopRideVisual")
		if old then
			old:Destroy()
		end
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if not (hrp and hrp:IsA("BasePart")) then
			return
		end
		local model = buildItemModel(itemId)
		model.Name = "ShopRideVisual"
		model:SetAttribute("RideId", itemId)
		local root = model.PrimaryPart
		if not root then
			model:Destroy()
			return
		end
		model:PivotTo((hrp :: BasePart).CFrame * rideOffset(itemId))
		model.Parent = char
		root.Anchored = false
		weld(hrp :: BasePart, root)
	end
	local function makeTool(item: any): Tool
		local tool = Instance.new("Tool")
		tool.Name = item.Name
		tool.CanBeDropped = false
		tool.RequiresHandle = true
		tool:SetAttribute("ShopItemId", item.Id)
		tool:SetAttribute("SpeedMult", item.SpeedMult or 1)
		tool:SetAttribute("Fly", item.Fly == true)
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.35, 1, 0.35)
		handle.Transparency = if item.Kind == "vehicle" then 1 else 0
		handle.CanCollide = false
		handle.Massless = true
		handle.Color = Color3.fromRGB(80, 55, 35)
		handle.Parent = tool
		if item.Kind ~= "vehicle" then
			local vis = buildItemModel(item.Id)
			vis.Parent = tool
			local visRoot = vis.PrimaryPart
			if visRoot then
				vis:PivotTo(handle.CFrame)
				weld(handle, visRoot)
			end
			tool.Grip = CFrame.new(0, -0.85, 0)
			local last = 0
			tool.Activated:Connect(function()
				if os.clock() - last < 0.45 then
					return
				end
				last = os.clock()
				local base = tool.Grip
				for i = 1, 6 do
					tool.Grip = base * CFrame.Angles(math.rad(-80 * (i / 6)), 0, 0)
					task.wait(0.02)
				end
				tool.Grip = base
			end)
		else
			tool.Grip = CFrame.new()
			tool.Equipped:Connect(function()
				local char = tool.Parent
				if char and char:IsA("Model") then
					attachRide(char, item.Id)
				end
			end)
			tool.Unequipped:Connect(function()
				local bag = tool.Parent
				local owner = bag and bag.Parent
				if owner and owner:IsA("Player") and owner.Character then
					local vis = owner.Character:FindFirstChild("ShopRideVisual")
					if vis then
						vis:Destroy()
					end
				end
			end)
		end
		return tool
	end
	local function giveOwnedTools(player: Player)
		local backpack = player:FindFirstChildOfClass("Backpack")
		if not backpack then
			return
		end
		for _, container in ipairs({ backpack, player.Character }) do
			if container then
				for _, child in ipairs(container:GetChildren()) do
					if child:IsA("Tool") and child:GetAttribute("ShopItemId") ~= nil then
						child:Destroy()
					end
				end
			end
		end
		for _, item in ipairs(catalog()) do
			if playerOwns(player, item) then
				makeTool(item).Parent = backpack
			end
		end
	end
	local function refreshSpeed(player: Player)
		local char = player.Character
		if not char then
			return
		end
		local best = 1
		for _, child in ipairs(char:GetChildren()) do
			if child:IsA("Tool") then
				local m = child:GetAttribute("SpeedMult")
				if type(m) == "number" and m > best then
					best = m
				end
			end
		end
		char:SetAttribute("ShopSpeedMult", best)
		PlayerData.ApplyStats(player)
	end
	local function hookCharacter(player: Player, char: Model)
		char.ChildAdded:Connect(function(child)
			if child:IsA("Tool") and child:GetAttribute("ShopItemId") ~= nil then
				task.defer(function()
					refreshSpeed(player)
					if child:GetAttribute("Fly") == true or child.Name == "Skateboard" or child.Name == "Magic Carpet" then
						local id = child:GetAttribute("ShopItemId")
						if type(id) == "string" then
							attachRide(char, id)
						end
					end
				end)
			end
		end)
		char.ChildRemoved:Connect(function(child)
			if child:IsA("Tool") then
				task.defer(function()
					refreshSpeed(player)
					local vis = char:FindFirstChild("ShopRideVisual")
					if vis then
						vis:Destroy()
					end
				end)
			end
		end)
		task.delay(0.4, function()
			if player.Parent then
				giveOwnedTools(player)
				PlayerData.ApplyStats(player)
			end
		end)
		task.delay(1.5, function()
			if player.Parent then
				PlayerData.ApplyStats(player)
			end
		end)
	end
	local function onPlayer(player: Player)
		player.CharacterAdded:Connect(function(char)
			hookCharacter(player, char)
		end)
		if player.Character then
			hookCharacter(player, player.Character)
		end
	end
	local function promptBuy(player: Player, item: any)
		if playerOwns(player, item) then
			giveOwnedTools(player)
			hint(player, "You already own " .. item.Name .. " — check your backpack.")
			return
		end
		local passId = passIdOf(item)
		if passId > 0 then
			MarketplaceService:PromptGamePassPurchase(player, passId)
			return
		end
		if RunService:IsStudio() then
			PlayerData.GrantShopItem(player, item.Id)
			giveOwnedTools(player)
			hint(player, item.Name .. " granted in Studio. Paste a GamePassId for live Robux sales.")
			return
		end
		hint(player, "Create a Game Pass for " .. item.Name .. " and paste GamePassId in BrainrotData.")
	end
	local function ownedList(player: Player): { string }
		local ids = {}
		for _, item in ipairs(catalog()) do
			if playerOwns(player, item) then
				table.insert(ids, item.Id)
			end
		end
		return ids
	end
	local function openShopUi(player: Player)
		local remotes = ReplicatedStorage:FindFirstChild("Remotes")
		local ev = remotes and remotes:FindFirstChild("OpenRobuxShop")
		if ev and ev:IsA("RemoteEvent") then
			ev:FireClient(player, { Items = catalog(), Owned = ownedList(player) })
		end
	end

	local spot = PlotSystem.PlazaSpots.Shop or PlotSystem.PlazaSpots.Fusion
	local cx, cz = spot.X, spot.Y
	local stall = Instance.new("Model")
	stall.Name = "RobuxShop"
	local gy = 16
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(cx, 500, cz), Vector3.new(0, -1000, 0), params)
	if hit then
		gy = hit.Position.Y
	end
	local function anchored(name: string, size: Vector3, pos: Vector3, color: Color3, mat: Enum.Material): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Position = pos
		p.Anchored = true
		p.Color = color
		p.Material = mat
		p.Parent = stall
		return p
	end
	local floor = anchored("Floor", Vector3.new(10, 0.6, 8), Vector3.new(cx, gy + 0.3, cz), Color3.fromRGB(70, 50, 36), Enum.Material.WoodPlanks)
	stall.PrimaryPart = floor
	anchored("Awning", Vector3.new(10, 0.4, 8), Vector3.new(cx, gy + 7.6, cz), Color3.fromRGB(180, 40, 50), Enum.Material.Fabric)
	anchored("PostL", Vector3.new(0.5, 7.2, 0.5), Vector3.new(cx - 4.5, gy + 3.9, cz - 3.5), Color3.fromRGB(90, 65, 40), Enum.Material.Wood)
	anchored("PostR", Vector3.new(0.5, 7.2, 0.5), Vector3.new(cx + 4.5, gy + 3.9, cz - 3.5), Color3.fromRGB(90, 65, 40), Enum.Material.Wood)
	anchored("Counter", Vector3.new(8, 1.2, 2), Vector3.new(cx, gy + 1.1, cz + 2.2), Color3.fromRGB(120, 85, 50), Enum.Material.Wood)
	local sign = anchored("Sign", Vector3.new(8, 2.2, 0.4), Vector3.new(cx, gy + 8.8, cz), Color3.fromRGB(28, 22, 18), Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.Parent = sign
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 1, 0)
	title.BackgroundTransparency = 1
	title.Text = "ROBUX SHOP"
	title.TextScaled = true
	title.Font = Enum.Font.GothamBlack
	title.TextColor3 = Color3.fromRGB(255, 220, 90)
	title.Parent = gui
	local back = gui:Clone()
	back.Face = Enum.NormalId.Back
	back.Parent = sign
	for i, item in ipairs(catalog()) do
		local px = cx - 3.5 + (i - 1) * 1.4
		local vis = buildItemModel(item.Id)
		vis:ScaleTo(if item.Id == "airplane" then 0.18 else 0.42)
		local root = vis.PrimaryPart
		if root then
			vis:PivotTo(CFrame.new(px, gy + 2.15, cz - 2.15) * CFrame.Angles(0, math.rad(25), 0))
			root.Anchored = true
		end
		vis.Parent = stall
	end

	local promptParent: BasePart = floor
	local npc: Model? = nil
	local okNpc, built = pcall(function()
		local desc = Instance.new("HumanoidDescription")
		desc.HeadColor = Color3.fromRGB(255, 204, 153)
		desc.TorsoColor = Color3.fromRGB(160, 40, 50)
		desc.LeftArmColor = Color3.fromRGB(255, 204, 153)
		desc.RightArmColor = Color3.fromRGB(255, 204, 153)
		desc.LeftLegColor = Color3.fromRGB(35, 35, 45)
		desc.RightLegColor = Color3.fromRGB(35, 35, 45)
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if okNpc and built and built:IsA("Model") then
		npc = built
	end
	if npc then
		npc.Name = "Shopkeeper"
		npc.Parent = stall
		npc:PivotTo(CFrame.new(cx, gy + 3, cz - 0.6))
		local hum = npc:FindFirstChildOfClass("Humanoid")
		if hum then
			hum.DisplayName = "Shopkeeper"
			hum.WalkSpeed = 0
			hum.JumpPower = 0
			hum.AutoJumpEnabled = false
		end
		for _, d in ipairs(npc:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
		local hrp = npc:FindFirstChild("HumanoidRootPart")
		if hrp and hrp:IsA("BasePart") then
			promptParent = hrp
		end
	end

	local shopPrompt = Instance.new("ProximityPrompt")
	shopPrompt.ActionText = "Talk"
	shopPrompt.ObjectText = "Shopkeeper"
	shopPrompt.HoldDuration = 0
	shopPrompt.MaxActivationDistance = 14
	shopPrompt.RequiresLineOfSight = false
	shopPrompt.Parent = promptParent
	shopPrompt.Triggered:Connect(openShopUi)

	local plaza = workspace:FindFirstChild("Plaza")
	stall.Parent = plaza or workspace
	print("[GameServer] Robux shop NPC at " .. tostring(Vector3.new(cx, gy, cz)))

	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	local buyEv = remotesFolder and remotesFolder:FindFirstChild("BuyShopItem")
	if buyEv and buyEv:IsA("RemoteEvent") then
		buyEv.OnServerEvent:Connect(function(player: Player, itemId: any)
			if type(itemId) ~= "string" then
				return
			end
			for _, item in ipairs(catalog()) do
				if item.Id == itemId then
					promptBuy(player, item)
					openShopUi(player)
					return
				end
			end
		end)
	end

	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local item = defByPass(passId)
		if not item then
			return
		end
		PlayerData.GrantShopItem(player, item.Id)
		giveOwnedTools(player)
		hint(player, "You bought " .. item.Name .. "!")
		openShopUi(player)
	end)
	Players.PlayerAdded:Connect(onPlayer)
	for _, existing in ipairs(Players:GetPlayers()) do
		task.defer(onPlayer, existing)
	end
end

return VisualEffects
