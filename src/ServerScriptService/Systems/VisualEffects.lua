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
	signLabel.Text = zone and zone.Name or "???"
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextScaled = true -- auto-fit, always readable
	signLabel.TextColor3 = Color3.new(1, 0.9, 0.3) -- gold text
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
		light.Position = bp + Vector3.new(0, 10, 0)
		light.Parent = fxFolder

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
		light.Position = bp + Vector3.new(0, 8, 0)
		light.Parent = fxFolder

	elseif themeId == "ocean" then
		-- Water ripples + blue fog
		base.Material = Enum.Material.Water
		base.Transparency = 0.2
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(50, 130, 180)
		light.Range = 25
		light.Brightness = 1.5
		light.Position = bp + Vector3.new(0, 8, 0)
		light.Parent = fxFolder

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
function VisualEffects.BuildColosseum(centerPos: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Colosseum"

	-- Outer wall (cylinder segments)
	local wallSegments = 16
	local radius = 30
	for i = 1, wallSegments do
		local angle = (i / wallSegments) * math.pi * 2
		local wall = Instance.new("Part")
		wall.Size = Vector3.new(8, 15, 3)
		wall.Color = Color3.fromRGB(180, 170, 160)
		wall.Material = Enum.Material.Marble
		wall.Anchored = true
		wall.Position = centerPos + Vector3.new(
			math.cos(angle) * radius,
			7.5,
			math.sin(angle) * radius
		)
		wall.Orientation = Vector3.new(0, -math.deg(angle) + 90, 0)
		wall.Parent = model

		-- Arch openings (every other segment is shorter)
		if i % 2 == 0 then
			wall.Size = Vector3.new(8, 8, 3)
			wall.Position = centerPos + Vector3.new(
				math.cos(angle) * radius,
				4,
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
	emblem.Size = Vector3.new(10, 0.5, 10)
	emblem.Shape = Enum.PartType.Cylinder
	emblem.Color = Color3.fromRGB(200, 50, 50)
	emblem.Material = Enum.Material.Marble
	emblem.Anchored = true
	emblem.Position = centerPos + Vector3.new(0, 0.8, 0)
	emblem.Parent = model

	-- Torches around the rim
	for i = 1, 8 do
		local angle = (i / 8) * math.pi * 2
		local torchPos = centerPos + Vector3.new(
			math.cos(angle) * (radius - 3),
			0,
			math.sin(angle) * (radius - 3)
		)
		-- Simple torch
		local post = Instance.new("Part")
		post.Size = Vector3.new(0.8, 6, 0.8)
		post.Color = Color3.fromRGB(90, 60, 35)
		post.Material = Enum.Material.Wood
		post.Anchored = true
		post.Position = torchPos + Vector3.new(0, 3, 0)
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
			math.cos(angle) * (radius - 1),
			12,
			math.sin(angle) * (radius - 1)
		)
		local banner = Instance.new("Part")
		banner.Size = Vector3.new(3, 6, 0.3)
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
	signLabel.Text = "🎣 FISHING\nCast from the dock!"
	signLabel.Font = Enum.Font.GothamBold
	signLabel.TextSize = 22
	signLabel.TextColor3 = Color3.new(1, 1, 1)
	signLabel.TextStrokeTransparency = 0.5
	signLabel.Parent = signGui

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
function VisualEffects.AddWildAura(model: Model, rarity: string)
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

	-- Name tag (shows rarity, not name — keeps mystery!)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WildTag"
	billboard.Size = UDim2.new(0, 80, 0, 26)
	billboard.StudsOffset = Vector3.new(0, 3.5, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = primary

	local tag = Instance.new("TextLabel")
	tag.Size = UDim2.new(1, 0, 1, 0)
	tag.BackgroundColor3 = color
	tag.BackgroundTransparency = 0.3
	tag.Text = "❓ " .. rarity
	tag.Font = Enum.Font.GothamBold
	tag.TextSize = 13
	tag.TextColor3 = Color3.new(1, 1, 1)
	tag.TextStrokeTransparency = 0.4
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = tag
	tag.Parent = billboard
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

return VisualEffects
