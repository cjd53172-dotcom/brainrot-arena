--!strict
--[[
	PlotSystem (ModuleScript -> ServerScriptService/Systems)
	Builds player showcase plots in code (no manual Studio building needed).

	Each plot has BrainrotData.SHOWCASE_LIMIT pedestals in fixed positions.
	RefreshPlot displays the player's curated Showcase list (instance IDs,
	in order) — NOT their whole inventory. Shiny instances render with
	shifted colors, gold name tags, and sparkle particles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrainrotData = require(ReplicatedStorage:WaitForChild("BrainrotData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local VisualEffects = require(script.Parent:WaitForChild("VisualEffects"))

local PlotSystem = {}

local PLOT_COUNT = 6
local PLOT_SIZE = 30
local PLOT_GAP = 8 -- space between adjacent plots in the row
-- WORLD OFFSET: shifts ALL gameplay (plots, obby, arena, fusion lab) to sit on
-- flat ground. Tune these if content is buried or floating on your terrain.
local WORLD_DX = 127
local WORLD_DZ = 98
-- Plots are lined up side-by-side along X, all facing +Z (front = +Z).

local plotsFolder: Folder? = nil
local playerPlots: { [number]: Model } = {} -- [userId] -> plot

local SHAPES = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local function newPart(props: { [string]: any }, parent: Instance): Part
	local rawShape = props.Shape
	local className = "Part"
	local shapeValue: any = nil
	if rawShape == "Wedge" then
		className = "WedgePart"
	elseif typeof(rawShape) == "EnumItem" then
		shapeValue = rawShape
	else
		shapeValue = SHAPES[rawShape] or Enum.PartType.Block
	end
	local clean = table.clone(props)
	clean.Shape = shapeValue
	local p = Instance.new(className)
	for key, value in pairs(clean) do
		if value ~= nil then
			(p :: any)[key] = value;
		end
	end
	p.Parent = parent
	return p
end

-- // Precise Platform Surface Alignment Helper ----------------------------------
-- Measures the exact bounding box of any model and places its lowest point
-- precisely on top of the target base/pedestal surface, preventing clipping.
local function modelAabb(model: Model): (Vector3?, Vector3?)
	local minX, minY, minZ = math.huge, math.huge, math.huge
	local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
	local found = false
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "RarityPlate" then
			local part = d :: BasePart
			local cf = part.CFrame
			local h = part.Size * 0.5
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						local p = (cf * CFrame.new(h.X * sx, h.Y * sy, h.Z * sz)).Position
						minX = math.min(minX, p.X)
						minY = math.min(minY, p.Y)
						minZ = math.min(minZ, p.Z)
						maxX = math.max(maxX, p.X)
						maxY = math.max(maxY, p.Y)
						maxZ = math.max(maxZ, p.Z)
						found = true
					end
				end
			end
		end
	end
	if not found then
		return nil
	end
	return Vector3.new(minX, minY, minZ), Vector3.new(maxX, maxY, maxZ)
end

local function placeModelOnTop(model: Model, targetPart: BasePart, extraOffset: number?)
	local minV, maxV = modelAabb(model)
	if not minV or not maxV then
		return
	end
	local target = Vector3.new(
		targetPart.Position.X,
		targetPart.Position.Y + targetPart.Size.Y / 2 + (extraOffset or 0),
		targetPart.Position.Z
	)
	local currentBottom = Vector3.new((minV.X + maxV.X) * 0.5, minV.Y, (minV.Z + maxV.Z) * 0.5)
	model:PivotTo(model:GetPivot() + (target - currentBottom))
end

-- // Pack auto-import ---------------------------------------------------------------
local function normName(s: string): string
	return string.lower(s):gsub("[%s_%-%.]", "")
end

local function fuzzyNameMatch(packName: string, def: any): boolean
	local packNorm = normName(packName)
	local idNorm = normName(def.Id)
	local nameNorm = normName(def.Name)

	if packNorm == idNorm or packNorm == nameNorm then
		return true
	end
	if string.find(packNorm, idNorm, 1, true) or string.find(idNorm, packNorm, 1, true) then
		return true
	end
	if string.find(packNorm, nameNorm, 1, true) or string.find(nameNorm, packNorm, 1, true) then
		return true
	end
	local packWords: { [string]: boolean } = {}
	local packWordCount = 0
	for w in string.gmatch(string.lower(packName), "%a+") do
		if not packWords[w] then
			packWords[w] = true
			packWordCount += 1
		end
	end
	if packWordCount >= 2 then
		local rosterWords: { [string]: boolean } = {}
		for w in string.gmatch(string.lower(def.Name), "%a+") do
			rosterWords[w] = true
		end
		local allFound = true
		for w in pairs(packWords) do
			if not rosterWords[w] then
				allFound = false
				break
			end
		end
		if allFound then
			return true
		end
	end
	return false
end

local PACK_OVERRIDES: { [string]: string } = {
	blueberrinni_octopusini = "blueberrinni",
}

local function packNameToId(packName: string): string?
	local want = normName(packName)
	local override = PACK_OVERRIDES[want]
	if override then
		return override
	end
	for _, def in ipairs(BrainrotData.ROSTER) do
		if fuzzyNameMatch(packName, def) then
			return def.Id
		end
	end
	return nil
end

local function autoImportPack()
	local rs = game:GetService("ReplicatedStorage")
	local folder = rs:FindFirstChild("BrainrotModels")
	if not (folder and folder:IsA("Folder")) then
		local f = Instance.new("Folder")
		f.Name = "BrainrotModels"
		f.Parent = rs
		folder = f
	end
	local modelsFolder = folder :: Folder

	local pack: Instance? = nil
	for _, root in ipairs({ workspace, rs }) do
		for _, d in ipairs(root:GetDescendants()) do
			if (d:IsA("Folder") or d:IsA("Model"))
				and d ~= modelsFolder
				and not d:IsDescendantOf(modelsFolder)
				and string.find(string.lower(d.Name), "brainrot", 1, true) then
				pack = d
				break
			end
		end
		if pack then
			break
		end
	end
	if not pack then
		return
	end

	local matched = 0
	local normalFolder: Instance? = nil
	for _, child in ipairs(pack:GetChildren()) do
		if child.Name:lower() == "normal"
			and (child:IsA("Folder") or child:IsA("Model")) then
			normalFolder = child
			break
		end
	end
	local source: Instance = normalFolder or pack
	for _, child in ipairs(source:GetChildren()) do
		if child:IsA("Model") or child:IsA("Folder") or child:IsA("BasePart") then
			if source == pack then
				local id = packNameToId(child.Name)
				if not id then
					continue
				end
			end
			table.insert({}, child)
		end
	end
	for _, child in ipairs(source:GetChildren()) do
		local id = packNameToId(child.Name)
		if id then
			matched += 1
		end
		if id and not modelsFolder:FindFirstChild(id) then
			local copy = child:Clone()
			for _, d in ipairs(copy:GetDescendants()) do
				if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
					or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
					d:Destroy()
				end
			end
			copy.Name = id
			copy.Parent = modelsFolder
		end
	end

	if matched > 0 then
		pcall(function()
			pack:Destroy()
		end)
	end
end

-- // Plot construction ----------------------------------------------------------
function PlotSystem.Setup()
	autoImportPack()
	local function groundY(x: number, z: number): number
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
		return r and r.Position.Y or 0
	end
	local function maxGroundY(cx: number, cz: number, half: number): number
		local m = groundY(cx, cz)
		for _, ox in ipairs({ -half, half }) do
			for _, oz in ipairs({ -half, half }) do
				local h = groundY(cx + ox, cz + oz)
				if h > m then m = h end
			end
		end
		return m
	end
	local function liftModel(model: Instance, dy: number)
		if dy == 0 then return end
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				(d :: BasePart).Position += Vector3.new(0, dy, 0)
			end
		end
	end

	local existing = workspace:FindFirstChild("Plots")
	if existing then
		existing:Destroy()
	end
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	pcall(function()
		local terrain = workspace.Terrain
		local region = Region3.new(
			Vector3.new(40, -5, -10),
			Vector3.new(260, 40, 340)
		):ExpandToGrid(4)
		local mats, occ = terrain:ReadVoxels(region, 4)
		local sx = #mats
		local sy = #mats[1]
		local sz = #mats[1][1]
		for xi = 1, sx do
			for yi = 1, sy do
				for zi = 1, sz do
					local m = mats[xi][yi][zi]
					if m == Enum.Material.Grass then
						mats[xi][yi][zi] = Enum.Material.Concrete
					end
				end
			end
		end
		terrain:WriteVoxels(region, 4, mats, occ)
	end)

	local limit = BrainrotData.SHOWCASE_LIMIT
	local perRow = 5

	local PLOT_COLS = 3
	local rowsTotal = math.ceil(PLOT_COUNT / PLOT_COLS)
	local function plotXZ(i: number): (number, number)
		local col = (i - 1) % PLOT_COLS
		local row = math.floor((i - 1) / PLOT_COLS)
		local x = (col - (PLOT_COLS - 1) / 2) * (PLOT_SIZE + PLOT_GAP) + WORLD_DX
		local z = (row - (rowsTotal - 1) / 2) * (PLOT_SIZE + PLOT_GAP) + WORLD_DZ
		return x, z
	end
	local uniformPlotY = 0
	for i = 1, PLOT_COUNT do
		local px, pz = plotXZ(i)
		local h = maxGroundY(px, pz, 15)
		if h > uniformPlotY then
			uniformPlotY = h
		end
	end
	uniformPlotY += 1

	for i = 1, PLOT_COUNT do
		local x, z = plotXZ(i)

		local plot = Instance.new("Model")
		plot.Name = "Plot" .. i
		plot:SetAttribute("Index", i)

		newPart({
			Name = "BaseBorder",
			Size = Vector3.new(PLOT_SIZE + 2, 1, PLOT_SIZE + 2),
			Position = Vector3.new(x, 0.4, z),
			Anchored = true,
			Material = Enum.Material.Cobblestone,
			Color = Color3.fromRGB(120, 120, 130),
		}, plot)
		newPart({
			Name = "Base",
			Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
			Position = Vector3.new(x, 0.6, z),
			Anchored = true,
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(95, 180, 95),
		}, plot)
		for _, cx in ipairs({ -1, 1 }) do
			for _, cz in ipairs({ -1, 1 }) do
				newPart({
					Name = "CornerPost",
					Size = Vector3.new(1.2, 4, 1.2),
					Position = Vector3.new(
						x + cx * (PLOT_SIZE / 2 - 0.6),
						2.5,
						z + cz * (PLOT_SIZE / 2 - 0.6)
					),
					Anchored = true,
					Material = Enum.Material.Wood,
					Color = Color3.fromRGB(140, 100, 60),
				}, plot)
			end
		end

		local sign = newPart({
			Name = "OwnerSign",
			Size = Vector3.new(8, 4, 0.6),
			Position = Vector3.new(x, 4, z + PLOT_SIZE / 2 - 1.5),
			Anchored = true,
			Color = Color3.fromRGB(150, 110, 70),
			Material = Enum.Material.Wood,
		}, plot)

		local signGui = Instance.new("SurfaceGui")
		signGui.Face = Enum.NormalId.Back
		signGui.Parent = sign
		local signLabel = Instance.new("TextLabel")
		signLabel.Size = UDim2.new(1, 0, 1, 0)
		signLabel.BackgroundTransparency = 1
		signLabel.Text = "Empty Plot"
		signLabel.TextScaled = true
		signLabel.Font = Enum.Font.GothamBold
		signLabel.TextColor3 = Color3.new(1, 1, 1)
		signLabel.TextStrokeTransparency = 0.6
		signLabel.Parent = signGui

		local pedestals = Instance.new("Folder")
		pedestals.Name = "Pedestals"
		pedestals.Parent = plot

		for slot = 1, limit do
			local row = math.floor((slot - 1) / perRow)
			local col = (slot - 1) % perRow
			local px = x - 10 + col * 5
			local pz = z - 4 + row * 8
			newPart({
				Name = "Pedestal_" .. slot,
				Size = Vector3.new(3, 1.2, 3),
				Position = Vector3.new(px, 1.6, pz),
				Anchored = true,
				Color = Color3.fromRGB(205, 205, 210),
				Material = Enum.Material.Marble,
			}, pedestals)
		end

		local stations = Instance.new("Folder")
		stations.Name = "Stations"
		stations.Parent = plot

		for sIdx, workId in ipairs(BrainrotData.WORK_ORDER) do
			local workDef = BrainrotData.WORK_TYPES[workId]
			local sx = x - 12 + (sIdx - 1) * 6
			local sz = z + 11

			local station = Instance.new("Model")
			station.Name = "Station_" .. workId

			newPart({
				Name = "Platform",
				Size = Vector3.new(5, 1, 5),
				Position = Vector3.new(sx, 1, sz),
				Anchored = true,
				Color = workDef.Color,
				Material = Enum.Material.SmoothPlastic,
			}, station)

			local signWork = newPart({
				Name = "WorkSign",
				Size = Vector3.new(4.4, 2, 0.4),
				Position = Vector3.new(sx, 3.4, sz + 2.2),
				Anchored = true,
				Color = Color3.fromRGB(90, 70, 50),
				Material = Enum.Material.Wood,
			}, station)
			local signWorkGui = Instance.new("SurfaceGui")
			signWorkGui.Face = Enum.NormalId.Back
			signWorkGui.Parent = signWork
			local signWorkLabel = Instance.new("TextLabel")
			signWorkLabel.Size = UDim2.new(1, 0, 1, 0)
			signWorkLabel.BackgroundTransparency = 1
			signWorkLabel.Text = workDef.Name .. "\n" .. workDef.Material
			signWorkLabel.TextScaled = true
			signWorkLabel.Font = Enum.Font.GothamBold
			signWorkLabel.TextColor3 = Color3.new(1, 1, 1)
			signWorkLabel.TextStrokeTransparency = 0.6
			signWorkLabel.Parent = signWorkGui

			for slot = 1, BrainrotData.STATION_SLOTS do
				newPart({
					Name = "WorkerSpot_" .. slot,
					Size = Vector3.new(2, 0.2, 2),
					Position = Vector3.new(sx - 1.3 + (slot - 1) * 2.6, 1.6, sz),
					Anchored = true,
					Color = Color3.fromRGB(220, 220, 225),
					Material = Enum.Material.SmoothPlastic,
				}, station)
			end

			station.Parent = stations
		end

		plot.Parent = plotsFolder
		liftModel(plot, uniformPlotY)
	end

	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = workspace

	local lab = Instance.new("Model")
	lab.Name = "FusionLab"
	newPart({
		Name = "Base",
		Size = Vector3.new(10, 1, 10),
		Position = Vector3.new(70 + WORLD_DX, 0.5, 0 + WORLD_DZ),
		Anchored = true,
		Color = Color3.fromRGB(60, 60, 80),
		Material = Enum.Material.SmoothPlastic,
	}, lab)
	newPart({
		Name = "Chamber",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(6, 5, 6),
		Position = Vector3.new(70 + WORLD_DX, 3.5, 0 + WORLD_DZ),
		Anchored = true,
		Color = Color3.fromRGB(150, 80, 220),
		Material = Enum.Material.Neon,
		CanCollide = false,
	}, lab)
	local labSign = newPart({
		Name = "Sign",
		Size = Vector3.new(9, 3, 0.6),
		Position = Vector3.new(70 + WORLD_DX, 7.5, 0 + WORLD_DZ),
		Anchored = true,
		Color = Color3.fromRGB(90, 70, 50),
		Material = Enum.Material.Wood,
	}, lab)
	local labGui = Instance.new("SurfaceGui")
	labGui.Face = Enum.NormalId.Front
	labGui.Parent = labSign
	local labLabel = Instance.new("TextLabel")
	labLabel.Size = UDim2.new(1, 0, 1, 0)
	labLabel.BackgroundTransparency = 1
	labLabel.Text = "FUSION LAB\n3 duplicates + materials"
	labLabel.TextScaled = true
	labLabel.Font = Enum.Font.GothamBold
	labLabel.TextColor3 = Color3.new(1, 1, 1)
	labLabel.TextStrokeTransparency = 0.6
	labLabel.Parent = labGui
	local labPrompt = Instance.new("ProximityPrompt")
	labPrompt.Name = "FusionPrompt"
	labPrompt.ActionText = "Open Fusion Lab"
	labPrompt.ObjectText = "Fusion Lab"
	labPrompt.HoldDuration = 0
	labPrompt.MaxActivationDistance = 14
	labPrompt.Parent = labSign
	lab.Parent = plaza
	liftModel(lab, groundY(70 + WORLD_DX, 0 + WORLD_DZ))
	PlotSystem.FusionPrompt = labPrompt

	local arena = Instance.new("Model")
	arena.Name = "Arena"
	newPart({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(44, 2, 44),
		Position = Vector3.new(0 + WORLD_DX, 1, -70 + WORLD_DZ),
		Anchored = true,
		Color = Color3.fromRGB(200, 170, 120),
		Material = Enum.Material.Sand,
	}, arena)
	newPart({
		Name = "Center",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(12, 2.4, 12),
		Position = Vector3.new(0 + WORLD_DX, 1.2, -70 + WORLD_DZ),
		Anchored = true,
		Color = Color3.fromRGB(180, 60, 60),
		Material = Enum.Material.SmoothPlastic,
	}, arena)
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "Gate" .. if side < 0 then "Blue" else "Red",
			Size = Vector3.new(6, 8, 1),
			Position = Vector3.new(side * 16 + WORLD_DX, 5, -70 + WORLD_DZ),
			Anchored = true,
			Color = if side < 0 then Color3.fromRGB(60, 120, 220) else Color3.fromRGB(220, 60, 60),
			Material = Enum.Material.SmoothPlastic,
		}, arena)
	end
	local arenaSign = newPart({
		Name = "Sign",
		Size = Vector3.new(14, 4, 0.8),
		Position = Vector3.new(0 + WORLD_DX, 9, -70 + 22 + WORLD_DZ),
		Anchored = true,
		Color = Color3.fromRGB(90, 70, 50),
		Material = Enum.Material.Wood,
	}, arena)
	local arenaGui = Instance.new("SurfaceGui")
	arenaGui.Face = Enum.NormalId.Back
	arenaGui.Parent = arenaSign
	local arenaLabel = Instance.new("TextLabel")
	arenaLabel.Size = UDim2.new(1, 0, 1, 0)
	arenaLabel.BackgroundTransparency = 1
	arenaLabel.Text = "⚔ ARENA ⚔\nBattle the rivals!"
	arenaLabel.TextScaled = true
	arenaLabel.Font = Enum.Font.GothamBold
	arenaLabel.TextColor3 = Color3.new(1, 1, 1)
	arenaLabel.TextStrokeTransparency = 0.6
	arenaLabel.Parent = arenaGui
	local arenaPrompt = Instance.new("ProximityPrompt")
	arenaPrompt.Name = "ArenaPrompt"
	arenaPrompt.ActionText = "Enter Arena"
	arenaPrompt.ObjectText = "Arena"
	arenaPrompt.HoldDuration = 0
	arenaPrompt.MaxActivationDistance = 16
	arenaPrompt.Parent = arenaSign
	arena.Parent = plaza
	liftModel(arena, groundY(0 + WORLD_DX, -70 + WORLD_DZ))
	PlotSystem.ArenaPrompt = arenaPrompt

	local arenaCenter = Vector3.new(0 + WORLD_DX, 2, -70 + WORLD_DZ)
	pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local r = workspace:Raycast(Vector3.new(0 + WORLD_DX, 500, -70 + WORLD_DZ), Vector3.new(0, -1000, 0), params)
		if r then
			arenaCenter = Vector3.new(0 + WORLD_DX, r.Position.Y + 1, -70 + WORLD_DZ)
		end
	end)
	local colosseum = VisualEffects.BuildColosseum(arenaCenter)
	colosseum.Parent = plaza

	local obby = Instance.new("Model")
	obby.Name = "CoinObby"

	local OBBY_X = 0 + WORLD_DX
	local OBBY_Z_START = 45 + WORLD_DZ

	newPart({
		Name = "StartPad",
		Size = Vector3.new(6, 1, 6),
		Position = Vector3.new(OBBY_X, 0.5, OBBY_Z_START),
		Anchored = true,
		Color = Color3.fromRGB(80, 200, 80),
		Material = Enum.Material.Grass,
	}, obby)

	local obbySign = newPart({
		Name = "ObbySign",
		Size = Vector3.new(10, 4, 0.6),
		Position = Vector3.new(OBBY_X, 5, OBBY_Z_START - 4),
		Anchored = true,
		Color = Color3.fromRGB(150, 110, 70),
		Material = Enum.Material.Wood,
	}, obby)
	local obbyGui = Instance.new("SurfaceGui")
	obbyGui.Face = Enum.NormalId.Back
	obbyGui.Parent = obbySign
	local obbyLabel = Instance.new("TextLabel")
	obbyLabel.Size = UDim2.new(1, 0, 1, 0)
	obbyLabel.BackgroundTransparency = 1
	obbyLabel.Text = "🪙 COIN JUMP 🪙\nGrab coins! Gold pad = 150 bonus!"
	obbyLabel.TextScaled = true
	obbyLabel.Font = Enum.Font.GothamBold
	obbyLabel.TextColor3 = Color3.new(1, 1, 1)
	obbyLabel.TextStrokeTransparency = 0.6
	obbyLabel.Parent = obbyGui

	local function makeCoin(parent: Instance, pos: Vector3, value: number)
		local coin = newPart({
			Name = "Coin",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(1.2, 1.5, 1.5),
			Position = pos,
			Anchored = true,
			CanCollide = false,
			Color = Color3.fromRGB(255, 200, 40),
			Material = Enum.Material.Neon,
		}, parent)
		coin:SetAttribute("Value", value)
		coin:SetAttribute("Collected", false)

		task.spawn(function()
			while coin and coin.Parent do
				local dt = task.wait()
				if coin:GetAttribute("Collected") then
					break
				end
				pcall(function()
					coin.CFrame = coin.CFrame * CFrame.Angles(0, math.rad(120) * dt, 0)
				end)
			end
		end)

		coin.Touched:Connect(function(hit: BasePart)
			if coin:GetAttribute("Collected") then
				return
			end
			local char = hit and hit.Parent
			local player = char and game:GetService("Players"):GetPlayerFromCharacter(char)
			if not player then
				return
			end
			coin:SetAttribute("Collected", true)
			PlayerData.AddCoins(player, value)
			pcall(function()
				local DQS = require(script.Parent:WaitForChild("DailyQuestSystem"))
				DQS.RecordProgress(player, "obby_coins", value)
			end)
			coin.Transparency = 1
			task.delay(30, function()
				if coin and coin.Parent then
					coin:SetAttribute("Collected", false)
					coin.Transparency = 0
					task.spawn(function()
						while coin and coin.Parent do
							local dt2 = task.wait()
							if coin:GetAttribute("Collected") then
								break
							end
							pcall(function()
								coin.CFrame = coin.CFrame * CFrame.Angles(0, math.rad(120) * dt2, 0)
							end)
						end
					end)
				end
			end)
		end)

		return coin
	end

	local platforms = {
		{ 0, 10, 2, 3.2 },
		{ 9, 22, 5, 2.8 },
		{ -10, 34, 3, 2.5 },
		{ 8, 48, 7, 2.5 },
		{ -9, 60, 4, 2.2 },
		{ 11, 74, 9, 2.5 },
		{ -11, 88, 6, 2.2 },
		{ 7, 102, 12, 2.5 },
		{ 0, 116, 10, 3.5 },
		{ -13, 130, 14, 2.2 },
		{ 10, 144, 11, 2.0 },
		{ 0, 158, 15, 3.0 },
	}

	local coinsFolder = Instance.new("Folder")
	coinsFolder.Name = "Coins"
	coinsFolder.Parent = obby

	for idx, p in ipairs(platforms) do
		local platPos = Vector3.new(OBBY_X + p[1], p[3], OBBY_Z_START + p[2])
		newPart({
			Name = "Platform_" .. idx,
			Size = Vector3.new(p[4], 1, p[4]),
			Position = platPos,
			Anchored = true,
			Color = Color3.fromRGB(100 + idx * 8, 150, 220),
			Material = Enum.Material.SmoothPlastic,
		}, obby)

		local coinCount = p[4] >= 3 and 2 or 1
		for c = 1, coinCount do
			local cxOff = coinCount == 2 and (c == 1 and -0.8 or 0.8) or 0
			makeCoin(coinsFolder, platPos + Vector3.new(cxOff, 2, 0), 15)
		end

		if idx == 9 then
			newPart({
				Name = "Checkpoint",
				Size = Vector3.new(p[4] + 0.5, 0.3, p[4] + 0.5),
				Position = platPos + Vector3.new(0, 0.65, 0),
				Anchored = true,
				CanCollide = false,
				Color = Color3.fromRGB(80, 220, 80),
				Material = Enum.Material.Neon,
			}, obby)
		end
	end

	local treasureSpots = {
		{ -80, -120, 2, 20 },
		{ 90, -110, 2, 20 },
		{ -120, -80, 3, 25 },
		{ 140, -70, 2, 20 },
		{ 0, -90, 15, 40 },
		{ -150, -40, 2, 20 },
		{ -180, 20, 3, 25 },
		{ -140, 80, 2, 20 },
		{ -200, 140, 4, 30 },
		{ -160, 200, 2, 20 },
		{ 150, -30, 2, 20 },
		{ 190, 40, 3, 25 },
		{ 160, 100, 2, 20 },
		{ 210, 160, 4, 30 },
		{ 170, 220, 2, 20 },
		{ -60, -160, 2, 20 },
		{ 60, -170, 3, 25 },
		{ -100, -200, 2, 20 },
		{ 100, -210, 5, 30 },
		{ 0, -240, 20, 50 },
		{ -80, 240, 2, 20 },
		{ 80, 250, 3, 25 },
		{ -130, 280, 2, 20 },
		{ 130, 290, 4, 30 },
		{ 0, 320, 2, 20 },
		{ -220, -180, 6, 40 },
		{ 230, -190, 6, 40 },
		{ -230, 300, 8, 40 },
		{ 240, 310, 8, 40 },
		{ 0, 0, 25, 50 },
		{ -90, 60, 12, 35 },
		{ 110, 130, 14, 35 },
		{ -70, 180, 16, 40 },
	}
	for _, t in ipairs(treasureSpots) do
		makeCoin(coinsFolder, Vector3.new(OBBY_X + t[1], t[3], OBBY_Z_START + t[2]), t[4])
	end

	local finishZ = OBBY_Z_START + 168
	local finishPad = newPart({
		Name = "FinishPad",
		Size = Vector3.new(6, 1, 6),
		Position = Vector3.new(OBBY_X, 13, finishZ),
		Anchored = true,
		Color = Color3.fromRGB(255, 200, 40),
		Material = Enum.Material.Neon,
	}, obby)
	makeCoin(coinsFolder, Vector3.new(OBBY_X, 15, finishZ), 50)

	local lastReward: { [number]: number } = {}
	finishPad.Touched:Connect(function(hit: BasePart)
		local char = hit and hit.Parent
		local player = char and game:GetService("Players"):GetPlayerFromCharacter(char)
		if not player then
			return
		end
		local now = os.clock()
		local last = lastReward[player.UserId] or 0
		if now - last < 60 then
			return
		end
		lastReward[player.UserId] = now
		PlayerData.AddCoins(player, 150)
		local origColor = finishPad.Color
		finishPad.Color = Color3.fromRGB(255, 255, 255)
		task.delay(0.3, function()
			if finishPad and finishPad.Parent then
				finishPad.Color = origColor
			end
		end)
	end)

	liftModel(obby, maxGroundY(OBBY_X, OBBY_Z_START + 50, 20) + 1)
	obby.Parent = workspace
end

function PlotSystem.AssignPlot(player: Player): Model?
	if not plotsFolder then
		return nil
	end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if plot:IsA("Model") and not plot:GetAttribute("OwnerId") then
			plot:SetAttribute("OwnerId", player.UserId)
			playerPlots[player.UserId] = plot

			local sign = plot:FindFirstChild("OwnerSign")
			if sign then
				local gui = sign:FindFirstChildOfClass("SurfaceGui")
				local label = gui and gui:FindFirstChildOfClass("TextLabel")
				if label then
					(label :: TextLabel).Text = player.DisplayName .. "'s Collection"
				end
			end
			return plot
		end
	end
	warn("[PlotSystem] No free plots for " .. player.Name)
	return nil
end

function PlotSystem.TeleportToPlot(player: Player)
	local plot = playerPlots[player.UserId]
	local char = player.Character
	if not plot or not char then
		return
	end
	local base = plot:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then
		return
	end
	local bp = (base :: BasePart).Position
	local dest = Vector3.new(bp.X, bp.Y + 5, bp.Z + 18)
	pcall(function()
		char:PivotTo(CFrame.new(dest))
	end)
end

function PlotSystem.GetPlot(player: Player): Model?
	return playerPlots[player.UserId]
end

function PlotSystem.ReleasePlot(player: Player)
	local plot = playerPlots[player.UserId]
	if plot then
		plot:SetAttribute("OwnerId", nil)
		local displays = plot:FindFirstChild("Displays")
		if displays then
			displays:Destroy()
		end
		local sign = plot:FindFirstChild("OwnerSign")
		if sign then
			local gui = sign:FindFirstChildOfClass("SurfaceGui")
			local label = gui and gui:FindFirstChildOfClass("TextLabel")
			if label then
				(label :: TextLabel).Text = "Empty Plot"
			end
		end
		playerPlots[player.UserId] = nil
	end
end

local function buildExtraPart(e: { [string]: any }, model: Model, variantTint: any, isShiny: boolean): Part
	local c = e.Color
	if variantTint then
		c = variantTint(c)
	end
	if isShiny then
		c = BrainrotData.GetShinyColor(c)
	end
	local p = newPart({
		Name = e.Name or "Extra",
		Shape = e.Shape,
		Size = e.Size,
		Color = c,
		Material = e.Material or Enum.Material.SmoothPlastic,
		Transparency = e.Transparency or 0,
		Anchored = true,
		CanCollide = false,
	}, model)
	local cf = CFrame.new(e.Offset or Vector3.new(0, 0, 0))
	if e.Rotation then
		cf = cf * CFrame.Angles(e.Rotation.X, e.Rotation.Y, e.Rotation.Z)
	end
	p.CFrame = cf
	return p
end

local function buildFace(model: Model, size: Vector3, mood: string?)
	local s = (size.X + size.Y) / 2
	local frontZ = size.Z / 2
	local eyeSize = math.clamp(s * 0.17, 0.28, 0.75)
	local eyeX = math.clamp(size.X * 0.19, 0.32, 1.3)
	local eyeY = size.Y * 0.17
	for _, sx in ipairs({ -1, 1 }) do
		local white = newPart({
			Name = "EyeWhite",
			Shape = "Ball",
			Size = Vector3.new(eyeSize, eyeSize * 1.15, eyeSize * 0.55),
			Color = Color3.new(1, 1, 1),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, model)
		white.CFrame = CFrame.new(sx * eyeX, eyeY, frontZ + eyeSize * 0.15)
		local pupil = newPart({
			Name = "Pupil",
			Shape = "Ball",
			Size = Vector3.new(eyeSize * 0.48, eyeSize * 0.55, eyeSize * 0.3),
			Color = Color3.new(0.05, 0.05, 0.08),
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, model)
		pupil.CFrame = CFrame.new(sx * eyeX, eyeY, frontZ + eyeSize * 0.42)
	end
	local mouthW = math.clamp(size.X * 0.3, 0.45, 1.5)
	local mouth = newPart({
		Name = "Mouth",
		Shape = "Ball",
		Size = Vector3.new(mouthW, mouthW * 0.45, 0.12),
		Color = Color3.fromRGB(45, 20, 25),
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
	}, model)
	mouth.CFrame = CFrame.new(0, -size.Y * 0.24, frontZ + 0.02)
	if mood == "angry" then
		for _, sx in ipairs({ -1, 1 }) do
			local brow = newPart({
				Name = "Brow",
				Size = Vector3.new(eyeSize * 1.15, 0.16, 0.12),
				Color = Color3.new(0.05, 0.05, 0.08),
				Material = Enum.Material.SmoothPlastic,
				Anchored = true,
				CanCollide = false,
			}, model)
			brow.CFrame = CFrame.new(sx * eyeX, eyeY + eyeSize * 0.85, frontZ + 0.06)
				* CFrame.Angles(0, 0, sx * -0.55)
		end
	end
end

local function addDressing(model: Model, height: number, def: any, variantId: string?, isShiny: boolean, host: BasePart?)
	local accentColor = BrainrotData.RARITY_COLORS[def.Rarity] or Color3.new(1, 1, 1)
	if isShiny then
		accentColor = Color3.fromRGB(255, 215, 0)
	end

	local plate = newPart({
		Name = "RarityPlate",
		Size = Vector3.new(3.6, 0.25, 3.6),
		Color = accentColor,
		Material = Enum.Material.Neon,
		Anchored = true,
		CanCollide = false,
	}, model)
	local bbCF, bbSize = model:GetBoundingBox()
	plate.CFrame = CFrame.new(bbCF.Position.X, bbCF.Position.Y - bbSize.Y / 2 - 0.15, bbCF.Position.Z)

	if isShiny and host then
		local sparkles = Instance.new("ParticleEmitter")
		sparkles.Name = "ShinySparkles"
		sparkles.Color = ColorSequence.new(Color3.fromRGB(255, 215, 0))
		sparkles.LightEmission = 1
		sparkles.Size = NumberSequence.new(0.45)
		sparkles.Rate = 14
		sparkles.Lifetime = NumberRange.new(0.6, 1.2)
		sparkles.Speed = NumberRange.new(2, 4)
		sparkles.SpreadAngle = Vector2.new(180, 180)
		sparkles.Parent = host
	end

	if not host then
		return
	end

	local tag = Instance.new("BillboardGui")
	tag.Name = "NameTag"
	tag.Size = UDim2.new(0, 260, 0, 70)
	tag.StudsOffset = Vector3.new(0, height / 2 + 1.6, 0)
	tag.AlwaysOnTop = true
	tag.Adornee = host

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.62, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = BrainrotData.GetDisplayName(def, variantId, isShiny)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextColor3 = isShiny and Color3.fromRGB(255, 215, 0) or Color3.new(1, 1, 1)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Parent = tag

	local rarityLabel = Instance.new("TextLabel")
	rarityLabel.Size = UDim2.new(1, 0, 0.38, 0)
	rarityLabel.Position = UDim2.new(0, 0, 0.62, 0)
	rarityLabel.BackgroundTransparency = 1
	rarityLabel.Text = string.upper(def.Rarity) .. (isShiny and " SHINY" or "")
	rarityLabel.TextScaled = true
	rarityLabel.Font = Enum.Font.GothamBold
	rarityLabel.TextColor3 = accentColor
	rarityLabel.TextStrokeTransparency = 0.4
	rarityLabel.Parent = tag

	tag.Parent = model
end

local function findCustomModel(def: any): Instance?
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not (folder and folder:IsA("Folder")) then
		return nil
	end
	local exact = folder:FindFirstChild(def.Id, true)
	if exact then
		return exact
	end
	for _, child in ipairs(folder:GetDescendants()) do
		if (child:IsA("Model") or child:IsA("Folder") or child:IsA("BasePart"))
			and fuzzyNameMatch(child.Name, def) then
			return child
		end
	end
	return nil
end

local function firstBasePart(model: Model): BasePart?
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			return d
		end
	end
	return nil
end

local function buildFromCustom(def: any, source: Instance, isShiny: boolean, variantId: string?): Model?
	local model: Model
	if source:IsA("Model") then
		model = (source :: Model):Clone()
	elseif source:IsA("Folder") then
		model = Instance.new("Model")
		for _, c in ipairs((source :: Folder):GetChildren()) do
			(c:Clone() :: Instance).Parent = model
		end
	elseif source:IsA("BasePart") then
		model = Instance.new("Model")
		;(source:Clone() :: Instance).Parent = model
	else
		return nil
	end
	model.Name = BrainrotData.GetDisplayName(def, variantId, isShiny)

	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
			or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			(d :: BasePart).Anchored = true
			(d :: BasePart).CanCollide = false
		end
	end

	local host = firstBasePart(model)
	if not host then
		model:Destroy()
		return nil
	end

	local function measure(): (CFrame?, Vector3?)
		local ok, bbCF, bbSize = pcall(function() return model:GetBoundingBox() end)
		if ok and bbCF and bbSize and bbSize.Y > 0.05 then
			return bbCF, bbSize
		end
		return nil, nil
	end

	local function manualScale(s: number)
		local bbCF = measure()
		if not bbCF then
			return
		end
		local center = (bbCF :: CFrame).Position
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				local part = d :: BasePart
				local rel: Vector3 = part.Position - center
				pcall(function()
					part.Size = part.Size * s
					part.CFrame = CFrame.new(center + rel * s) * (part.CFrame - part.CFrame.Position)
				end)
				for _, m in ipairs(part:GetChildren()) do
					if m:IsA("SpecialMesh") then
						pcall(function()
							(m :: SpecialMesh).Scale = (m :: SpecialMesh).Scale * s
						end)
					elseif m:IsA("DataModelMesh") then
						pcall(function()
							(m :: DataModelMesh).Scale = (m :: DataModelMesh).Scale * s
						end)
					end
				end
			end
		end
	end

	local targetH = def.Display.Size.Y
	local h = targetH

	for _ = 1, 4 do
		local _, bbSize = measure()
		if not bbSize then
			break
		end
		h = bbSize.Y
		local s = targetH / h
		if math.abs(s - 1) <= 0.03 then
			break
		end
		s = math.clamp(s, 0.02, 20)
		pcall(function() model:ScaleTo(s) end)
		local _, afterSize = measure()
		local afterH = afterSize and afterSize.Y or h
		if math.abs(afterH - h) < (h * 0.05) then
			manualScale(s)
		end
	end

	local bbCF = measure()
	if bbCF then
		local p = (bbCF :: CFrame).Position
		pcall(function()
			model:PivotTo(model:GetPivot() + Vector3.new(-p.X, -p.Y, -p.Z))
		end)
	end

	addDressing(model, h, def, variantId, isShiny, host)
	return model
end

function PlotSystem.BuildDisplayModel(def: any, isShiny: boolean, variantId: string?): Model
	local custom = findCustomModel(def)
	if custom then
		local fromCustom = buildFromCustom(def, custom, isShiny, variantId)
		if fromCustom then
			return fromCustom
		end
	end

	local model = Instance.new("Model")
	model.Name = BrainrotData.GetDisplayName(def, variantId, isShiny)

	local spec = def.Display
	local variantTint = BrainrotData.GetVariantTint(variantId)
	local bodyColor = spec.Color
	if variantTint then
		bodyColor = variantTint(bodyColor)
	end
	if isShiny then
		bodyColor = BrainrotData.GetShinyColor(bodyColor)
	end

	local body = newPart({
		Name = "Body",
		Shape = spec.Shape,
		Size = spec.Size,
		Position = Vector3.new(0, 0, 0),
		Color = bodyColor,
		Material = Enum.Material.SmoothPlastic,
		Anchored = true,
		CanCollide = false,
	}, model)

	if spec.Accessory then
		local a = spec.Accessory
		local accColor = a.Color
		if variantTint then
			accColor = variantTint(accColor)
		end
		if isShiny then
			accColor = BrainrotData.GetShinyColor(accColor)
		end
		local acc = newPart({
			Name = "Accessory",
			Shape = a.Shape,
			Size = a.Size,
			Color = accColor,
			Material = Enum.Material.SmoothPlastic,
			Anchored = true,
			CanCollide = false,
		}, model)
		local cf = CFrame.new(a.Offset)
		if a.Rotation then
			cf = cf * CFrame.Angles(a.Rotation.X, a.Rotation.Y, a.Rotation.Z)
		end
		acc.CFrame = cf
	end

	if spec.Extras then
		for _, e in ipairs(spec.Extras) do
			buildExtraPart(e, model, variantTint, isShiny)
		end
	end

	if spec.Face then
		local mood = if spec.Face == true then "happy" else spec.Face
		buildFace(model, spec.Size, mood)
	end

	addDressing(model, spec.Size.Y, def, variantId, isShiny, body)
	return model
end

-- Render the player's curated Showcase (slot N -> pedestal N).
function PlotSystem.RefreshPlot(player: Player)
	local plot = playerPlots[player.UserId]
	if not plot then
		return
	end
	local data = PlayerData.Get(player)
	if not data then
		return
	end

	local old = plot:FindFirstChild("Displays")
	if old then
		old:Destroy()
	end
	local displays = Instance.new("Folder")
	displays.Name = "Displays"
	displays.Parent = plot

	local pedestals = plot:FindFirstChild("Pedestals")
	if not pedestals then
		return
	end

	for slot, instanceId in ipairs(data.Showcase) do
		local inst = PlayerData.GetInstance(player, instanceId)
		local def = inst and BrainrotData.GetById(inst.BrainrotId)
		local ped = pedestals:FindFirstChild("Pedestal_" .. slot)
		if def and ped and ped:IsA("BasePart") then
			local display = PlotSystem.BuildDisplayModel(def, inst.Shiny == true, inst.Variant)
			display:SetAttribute("BrainrotId", def.Id)
			display.Parent = displays
			placeModelOnTop(display, ped, 0.1)
			local pedRef = ped
			task.defer(function()
				if display.Parent and pedRef.Parent then
					placeModelOnTop(display, pedRef, 0.1)
				end
			end)
		end
	end

	PlotSystem.ApplyCustomization(player, plot)
end

function PlotSystem.ApplyCustomization(player: Player, plot: Model)
	local data = PlayerData.Get(player)
	if not data then return end

	VisualEffects.ApplyTheme(plot, data.PlotTheme or "default")

	local oldDeco = plot:FindFirstChild("Decorations")
	if oldDeco then oldDeco:Destroy() end
	local decoFolder = Instance.new("Folder")
	decoFolder.Name = "Decorations"
	decoFolder.Parent = plot

	local base = plot:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then return end
	local bp = (base :: BasePart).Position
	local bs = (base :: BasePart).Size

	local baseTopY = bp.Y + bs.Y / 2
	local decoSpots = {
		Vector3.new(bp.X - bs.X/2 + 4, baseTopY, bp.Z - bs.Z/2 + 4),
		Vector3.new(bp.X + bs.X/2 - 4, baseTopY, bp.Z - bs.Z/2 + 4),
		Vector3.new(bp.X - bs.X/2 + 4, baseTopY, bp.Z + bs.Z/2 - 4),
		Vector3.new(bp.X + bs.X/2 - 4, baseTopY, bp.Z + bs.Z/2 - 4),
	}
	local spotIdx = 1
	for decoId, _ in pairs(data.Decorations or {}) do
		if spotIdx > #decoSpots then break end
		local pos = decoSpots[spotIdx]
		spotIdx += 1
		local decoModel = VisualEffects.BuildDecoration(decoId)
		decoModel:PivotTo(CFrame.new(pos))
		decoModel.Parent = decoFolder
	end
end

function PlotSystem.RefreshEggs(player: Player)
	local plot = playerPlots[player.UserId]
	if not plot then return end
	local data = PlayerData.Get(player)
	if not data then return end

	local oldEggs = plot:FindFirstChild("Eggs")
	if oldEggs then oldEggs:Destroy() end
	local eggFolder = Instance.new("Folder")
	eggFolder.Name = "Eggs"
	eggFolder.Parent = plot

	local base = plot:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then return end
	local bp = (base :: BasePart).Position
	local bs = (base :: BasePart).Size

	local idx = 0
	for eggId, egg in pairs(data.Eggs or {}) do
		idx += 1
		if idx > 5 then break end
		local eggModel = VisualEffects.BuildEgg(egg.Tier)
		local x = bp.X - bs.X/2 + 5 + (idx - 1) * 6
		local z = bp.Z - bs.Z/2 + 5
		eggModel:PivotTo(CFrame.new(Vector3.new(x, bp.Y + 2.5, z)))
		eggModel.Parent = eggFolder
		eggModel:SetAttribute("EggId", eggId)
	end
end

function PlotSystem.PlayHatch(player: Player, eggId: string, brainrotDef: any)
	local plot = playerPlots[player.UserId]
	if not plot then return end
	local eggFolder = plot:FindFirstChild("Eggs")
	if not eggFolder then return end

	for _, eggModel in ipairs(eggFolder:GetChildren()) do
		if eggModel:GetAttribute("EggId") == eggId and eggModel:IsA("Model") then
			VisualEffects.PlayHatch(eggModel, function()
				if brainrotDef then
					local display = PlotSystem.BuildDisplayModel(brainrotDef, false, nil)
					local base = plot:FindFirstChild("Base")
					if base and base:IsA("BasePart") then
						display.Parent = plot
						placeModelOnTop(display, base :: BasePart, 0.5)
						for _, desc in ipairs(display:GetDescendants()) do
							if desc:IsA("BasePart") then
								desc.Transparency = 1
							end
						end
						for i = 1, 10 do
							for _, desc in ipairs(display:GetDescendants()) do
								if desc:IsA("BasePart") then
									desc.Transparency = 1 - (i / 10)
								end
							end
							task.wait(0.05)
						end
						task.delay(3, function()
							if display and display.Parent then
								display:Destroy()
							end
							PlotSystem.RefreshPlot(player)
						end)
					end
				end
			end)
			break
		end
	end
end

function PlotSystem.SpawnMaterialPickups(player: Player, materials: { [string]: number })
	local plot = playerPlots[player.UserId]
	if not plot then return end
	local base = plot:FindFirstChild("Base")
	if not base or not base:IsA("BasePart") then return end
	local bp = (base :: BasePart).Position
	local bs = (base :: BasePart).Size

	local pickupsFolder = plot:FindFirstChild("MaterialPickups")
	if not pickupsFolder then
		pickupsFolder = Instance.new("Folder")
		pickupsFolder.Name = "MaterialPickups"
		pickupsFolder.Parent = plot
	end

	for matName, count in pairs(materials) do
		for i = 1, math.min(count, 5) do
			local matModel = VisualEffects.BuildMaterial(matName)
			local x = bp.X + (math.random() - 0.5) * bs.X * 0.7
			local z = bp.Z + (math.random() - 0.5) * bs.Z * 0.7
			matModel:PivotTo(CFrame.new(Vector3.new(x, bp.Y + 2, z)))
			matModel.Parent = pickupsFolder

			local part = matModel.PrimaryPart
			if part and part:IsA("BasePart") then
				(part :: BasePart).Touched:Connect(function(hit: BasePart)
					local char = hit and hit.Parent
					local p = char and game:GetService("Players"):GetPlayerFromCharacter(char)
					if p == player then
						local burstEmitter = Instance.new("ParticleEmitter")
						burstEmitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
						burstEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 200))
						burstEmitter.Size = NumberSequence.new(0.8)
						burstEmitter.Speed = NumberRange.new(5, 10)
						burstEmitter.Lifetime = NumberRange.new(0.3, 0.6)
						burstEmitter.Rate = 50
						burstEmitter.Parent = part
						task.wait(0.2)
						if matModel and matModel.Parent then
							matModel:Destroy()
						end
					end
				end)
			end
			task.delay(60, function()
				if matModel and matModel.Parent then
					matModel:Destroy()
				end
			end)
		end
	end
end

function PlotSystem.RefreshWorkers(player: Player)
	local plot = playerPlots[player.UserId]
	if not plot then
		return
	end
	local data = PlayerData.Get(player)
	if not data then
		return
	end

	local old = plot:FindFirstChild("Workers")
	if old then
		old:Destroy()
	end
	local workersFolder = Instance.new("Folder")
	workersFolder.Name = "Workers"
	workersFolder.Parent = plot

	local stations = plot:FindFirstChild("Stations")
	if not stations then
		return
	end

	for instanceId, job in pairs(data.Jobs) do
		local inst = PlayerData.GetInstance(player, instanceId)
		local def = inst and BrainrotData.GetById(inst.BrainrotId)
		local station = stations:FindFirstChild("Station_" .. tostring(job.Station))
		local spot = station and station:FindFirstChild("WorkerSpot_" .. tostring(job.Slot))
		if def and spot and spot:IsA("BasePart") then
			local display = PlotSystem.BuildDisplayModel(def, inst.Shiny == true, inst.Variant)
			display.Parent = workersFolder
			-- Align precisely on top of the worker spot
			placeModelOnTop(display, spot, 0.05)
		end
	end
end

-- // Battle arena visuals v2 ----------------------------------------------------
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local battleArenas: { [number]: any } = {}

local TYPE_FX: { [string]: Color3 } = {
	Wood = Color3.fromRGB(90, 210, 90),
	Water = Color3.fromRGB(70, 150, 255),
	Fire = Color3.fromRGB(255, 130, 40),
	Sky = Color3.fromRGB(160, 225, 255),
	Shadow = Color3.fromRGB(150, 70, 210),
}

local function typeColor(t: string?): Color3
	return TYPE_FX[t or ""] or Color3.fromRGB(255, 255, 255)
end

local function arenaFloorTop(): number
	local plaza = workspace:FindFirstChild("Plaza")
	local arena = plaza and plaza:FindFirstChild("Arena")
	local floor = arena and arena:FindFirstChild("Floor")
	if floor and floor:IsA("BasePart") then
		return (floor :: BasePart).Position.Y + (floor :: BasePart).Size.Y / 2
	end
	return 2
end

local function arenaCenterXZ(): (number, number)
	return WORLD_DX, -70 + WORLD_DZ
end

local function battleBaseCF(x: number, z: number, sizeY: number, faceAngle: number): CFrame
	return CFrame.new(x, arenaFloorTop() + 0.35 + sizeY / 2, z) * CFrame.Angles(0, faceAngle, 0)
end

local function tweenPivot(handle: any, targetCF: CFrame, dur: number): ()
	if not handle or not handle.model or not handle.model.Parent then
		return
	end
	local model = handle.model :: Model
	local cv = Instance.new("CFrameValue")
	cv.Value = model:GetPivot()
	local conn: RBXScriptConnection? = nil
	conn = cv:GetPropertyChangedSignal("Value"):Connect(function()
		if model.Parent then
			pcall(function()
				model:PivotTo(cv.Value)
			end)
		end
	end)
	local tw = TweenService:Create(
		cv,
		TweenInfo.new(dur, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = targetCF }
	)
	tw:Play()
	tw.Completed:Connect(function()
		if conn then
			conn:Disconnect()
		end
		cv:Destroy()
	end)
end

local function rotOnly(cf: CFrame): CFrame
	return cf - cf.Position
end

local function burst(parent: Instance, pos: Vector3, color: Color3, count: number?, speed: number?, size: number?)
	local p = Instance.new("Part")
	p.Name = "FXBurst"
	p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.CFrame = CFrame.new(pos)
	p.Anchored = true
	p.CanCollide = false
	p.Transparency = 1
	p.Parent = parent
	local em = Instance.new("ParticleEmitter")
	em.Color = ColorSequence.new(color)
	em.LightEmission = 0.8
	em.Size = NumberSequence.new(size or 0.7)
	em.Speed = NumberRange.new((speed or 12) * 0.5, speed or 12)
	em.Lifetime = NumberRange.new(0.4, 0.8)
	em.SpreadAngle = Vector2.new(180, 180)
	em.Rate = 0
	em.Parent = p
	em:Emit(count or 18)
	Debris:AddItem(p, 1.5)
end

local function ringBurst(parent: Instance, pos: Vector3, color: Color3, maxR: number?)
	local r = Instance.new("Part")
	r.Name = "FXRing"
	r.Shape = Enum.PartType.Cylinder
	r.Size = Vector3.new(0.4, 2, 2)
	r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2)
	r.Anchored = true
	r.CanCollide = false
	r.Color = color
	r.Material = Enum.Material.Neon
	r.Transparency = 0.25
	r.Parent = parent
	local target = maxR or 10
	local tw = TweenService:Create(r, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.4, target * 2, target * 2),
		Transparency = 1,
	})
	tw:Play()
	Debris:AddItem(r, 0.7)
end

local function damageNumber(parent: Instance, pos: Vector3, text: string, color: Color3, big: boolean?)
	local holder = Instance.new("Part")
	holder.Name = "FXDmgHolder"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(pos)
	holder.Anchored = true
	holder.CanCollide = false
	holder.Transparency = 1
	holder.Parent = parent
	local gui = Instance.new("BillboardGui")
	gui.Name = "FXDmg"
	gui.Size = UDim2.new(0, 140, 0, 56)
	gui.StudsOffset = Vector3.new(0, 2.2, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = holder
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextSize = if big then 34 else 24
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.15
	label.Parent = gui
	gui.Parent = parent
	task.spawn(function()
		for i = 1, 22 do
			task.wait(0.045)
			if not gui.Parent then
				break
			end
			gui.StudsOffset += Vector3.new(0, 0.28, 0)
			local a = i / 22
			label.TextTransparency = a
			label.TextStrokeTransparency = 0.15 + a * 0.85
		end
		if holder.Parent then
			holder:Destroy()
		end
		if gui.Parent then
			gui:Destroy()
		end
	end)
end

local function flashModel(handle: any, dur: number?)
	if not handle or not handle.model or not handle.model.Parent then
		return
	end
	task.spawn(function()
		local saved: { [BasePart]: Color3 } = {}
		for _, d in ipairs((handle.model :: Model):GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "RarityPlate" then
				local bp = d :: BasePart
				saved[d] = bp.Color
				bp.Color = Color3.new(1, 1, 1)
			end
		end
		task.wait(dur or 0.12)
		for part, col in pairs(saved) do
			if part and part.Parent then
				part.Color = col
			end
		end
	end)
end

local function fireProjectile(folder: Instance, fromPos: Vector3, toPos: Vector3, color: Color3, big: boolean?): Vector3
	local proj = Instance.new("Part")
	proj.Name = "FXProj"
	proj.Shape = Enum.PartType.Ball
	local s = if big then 1.7 else 1.1
	proj.Size = Vector3.new(s, s, s)
	proj.CFrame = CFrame.new(fromPos)
	proj.Anchored = true
	proj.CanCollide = false
	proj.Color = color
	proj.Material = Enum.Material.Neon
	proj.Parent = folder
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 12
	light.Brightness = 2
	light.Parent = proj
	local att0 = Instance.new("Attachment")
	att0.Parent = proj
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0.15, 0)
	att1.Parent = proj
	local trail = Instance.new("Trail")
	trail.Color = ColorSequence.new(color)
	trail.LightEmission = 1
	trail.Lifetime = 0.4
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Parent = proj
	local dur = 0.38
	local steps = 12
	for i = 1, steps do
		local t = i / steps
		local pos = fromPos:Lerp(toPos, t)
		pos += Vector3.new(0, math.sin(t * math.pi) * 2.5, 0)
		if proj.Parent then
			proj.CFrame = CFrame.new(pos)
		end
		task.wait(dur / steps)
	end
	local hitPos = toPos
	if proj.Parent then
		hitPos = proj.Position
		proj:Destroy()
	end
	burst(folder, hitPos, color, if big then 30 else 18, if big then 20 else 12, if big then 1.0 else 0.7)
	return hitPos
end

local function attachHpBar(folder: Instance, model: Model, sizeY: number, hp: number, maxHp: number): any
	local gui = Instance.new("BillboardGui")
	gui.Name = "FighterHp"
	gui.Size = UDim2.new(0, 96, 0, 14)
	gui.StudsOffset = Vector3.new(0, sizeY / 2 + 1.4, 0)
	gui.AlwaysOnTop = true
	local host = model:FindFirstChild("Body")
	if not host then
		host = model:FindFirstChildWhichIsA("BasePart")
	end
	if host then
		gui.Adornee = host
	end
	local back = Instance.new("Frame")
	back.Size = UDim2.new(1, 0, 1, 0)
	back.BackgroundColor3 = Color3.fromRGB(40, 10, 10)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(math.clamp(hp / math.max(1, maxHp), 0, 1), 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(90, 220, 90)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = folder
	return { gui = gui, fill = fill }
end

local function setHpBar(bar: any, hp: number, maxHp: number)
	if not bar or not bar.fill or not bar.fill.Parent then
		return
	end
	local frac = math.clamp(hp / math.max(1, maxHp), 0, 1)
	bar.fill.Size = UDim2.new(frac, 0, 1, 0)
	bar.fill.BackgroundColor3 = if frac > 0.5 then Color3.fromRGB(90, 220, 90)
		elseif frac > 0.25 then Color3.fromRGB(230, 200, 60)
		else Color3.fromRGB(230, 70, 70)
end

local function startIdle(handle: any)
	handle.bobbing = true
	task.spawn(function()
		local t = math.random() * 10
		while handle.bobbing and handle.model and handle.model.Parent do
			if not handle.frozen and not handle.fainted then
				t += 0.12
				local base: CFrame = handle.baseCF
				local bobY = math.sin(t * 2.2) * 0.22
				local sway = math.sin(t * 1.1) * 0.07
				pcall(function()
					handle.model:PivotTo(base * CFrame.new(sway, bobY, 0))
				end)
			end
			task.wait(0.12)
		end
		pcall(function()
			if handle.model and handle.model.Parent and not handle.fainted then
				handle.model:PivotTo(handle.baseCF)
			end
		end)
	end)
end

local BLAST_WORDS = { "beam", "blast", "ball", "wave", "storm", "breath", "veil", "bloom", "current", "spout", "cyclone", "eruption", "meteor", "surge", "torrent" }
local function moveKind(moveName: string?, power: number?): string
	local n = string.lower(moveName or "")
	for _, w in ipairs(BLAST_WORDS) do
		if string.find(n, w, 1, true) then
			return "blast"
		end
	end
	if (power or 0) >= 70 then
		return "heavy"
	end
	return "strike"
end

function PlotSystem.SpawnBattleModels(player: Player, pFighters: any, eFighters: any)
	PlotSystem.ClearBattleModels(player)
	local folder = Instance.new("Folder")
	folder.Name = "Battle_" .. tostring(player.UserId)
	folder.Parent = workspace
	local cx, cz = arenaCenterXZ()

	local function spawnOne(f: any, x: number, z: number, faceAngle: number, delay: number): any?
		local def = f and BrainrotData.GetById(f.BrainrotId)
		if not def then
			return nil
		end
		local model = PlotSystem.BuildDisplayModel(def, f.Shiny == true, f.Variant)
		local sizeY = def.Display.Size.Y
		local modelRot = model:GetPivot() - model:GetPivot().Position
		local baseCF = battleBaseCF(x, z, sizeY, faceAngle) * modelRot
		model:PivotTo(baseCF * CFrame.new(0, -7, 0))
		model.Parent = folder
		local maxHp = f.MaxHP or 100
		local handle: any = {
			model = model,
			baseCF = baseCF,
			sizeY = sizeY,
			fainted = false,
			bobbing = false,
			frozen = false,
			maxHp = maxHp,
		}
		handle.hpBar = attachHpBar(folder, model, sizeY, f.HP or maxHp, maxHp)
		task.spawn(function()
			task.wait(delay)
			if not model.Parent then
				return
			end
			burst(folder, baseCF.Position, Color3.fromRGB(200, 200, 200), 14, 10, 0.9)
			tweenPivot(handle, baseCF, 0.55)
			task.wait(0.6)
			if model.Parent then
				startIdle(handle)
			end
		end)
		return handle
	end

	local rec: any = { folder = folder, pModels = {}, eModels = {} }
	for i, f in ipairs(pFighters) do
		rec.pModels[i] = spawnOne(f, cx - 8, cz - 4 + (i - 1) * 4, math.pi / 2, (i - 1) * 0.25)
	end
	for i, f in ipairs(eFighters) do
		rec.eModels[i] = spawnOne(f, cx + 8, cz - 4 + (i - 1) * 4, -math.pi / 2, 0.5 + (i - 1) * 0.25)
	end
	battleArenas[player.UserId] = rec
	task.wait(1.8)
end

function PlotSystem.ClearBattleModels(player: Player)
	local rec = battleArenas[player.UserId]
	if rec then
		battleArenas[player.UserId] = nil
		for _, team in ipairs({ rec.pModels, rec.eModels }) do
			for _, h in ipairs(team) do
				if h then
					h.bobbing = false
				end
			end
		end
		local folder = rec.folder
		if folder then
			task.delay(0.3, function()
				if folder.Parent then
					folder:Destroy()
				end
			end)
		end
	end
end

function PlotSystem.PlayBattleEvent(player: Player, event: any)
	local rec = battleArenas[player.UserId]
	if not rec or not event then
		return
	end
	local atkTeam = if event.attackerSide == "player" then rec.pModels else rec.eModels
	local tgtTeam = if event.targetSide == "player" then rec.pModels else rec.eModels
	local atk = atkTeam[event.attackerIdx]
	local tgt = tgtTeam[event.targetIdx]
	if not atk or atk.fainted or not atk.model.Parent then
		return
	end
	local folder = rec.folder
	local fxColor = typeColor(event.moveType)
	local kind = moveKind(event.moveName, event.movePower)
	local atkBase: CFrame = atk.baseCF
	local atkDir = if event.attackerSide == "player" then 1 else -1

	atk.frozen = true
	if tgt then
		tgt.frozen = true
	end

	local function doImpact(tgtPos: Vector3, big: boolean)
		burst(folder, tgtPos, fxColor, if big then 32 else 18, if big then 22 else 13, if big then 1.0 else 0.7)
		if event.effectiveness and event.effectiveness > 1 then
			ringBurst(folder, tgtPos - Vector3.new(0, 0.5, 0), fxColor, 9)
			damageNumber(folder, tgtPos + Vector3.new(0, 3.4, 0), "SUPER EFFECTIVE!", Color3.fromRGB(255, 170, 80), true)
		elseif event.effectiveness and event.effectiveness < 1 then
			damageNumber(folder, tgtPos + Vector3.new(0, 3.4, 0), "resisted...", Color3.fromRGB(150, 150, 200), false)
		end
		if tgt then
			flashModel(tgt, 0.12)
			if not tgt.fainted then
				local tBase: CFrame = tgt.baseCF
				local away = tgtPos - atkBase.Position
				away = Vector3.new(away.X, 0, away.Z)
				if away.Magnitude > 0.01 then
					away = away.Unit
					local dist = if big then 2.4 elseif event.crit then 1.8 else 1.0
					tweenPivot(tgt, CFrame.new(tBase.Position + away * dist) * rotOnly(tBase), 0.16)
				end
			end
		end
		local dmgText = tostring(event.damage or 0)
		if event.crit then
			dmgText ..= "!"
		end
		damageNumber(folder, tgtPos + Vector3.new(0, 2.0, 0),
			dmgText, if event.crit then Color3.fromRGB(255, 220, 60) else Color3.new(1, 1, 1), event.crit)
		if event.crit then
			damageNumber(folder, tgtPos + Vector3.new(0, 4.6, 0), "CRITICAL HIT!", Color3.fromRGB(255, 200, 50), true)
			burst(folder, tgtPos, Color3.fromRGB(255, 230, 120), 24, 18, 0.8)
		end
		if tgt and tgt.hpBar and event.targetHp ~= nil then
			setHpBar(tgt.hpBar, event.targetHp, tgt.maxHp)
		end
		task.wait(0.4)
		if tgt and event.fainted and not tgt.fainted then
			tgt.fainted = true
			tgt.bobbing = false
			local tBase2: CFrame = tgt.baseCF
			local tipCF = CFrame.new(tBase2.Position + Vector3.new(0, -tgt.sizeY * 0.3, 0))
				* rotOnly(tBase2)
				* CFrame.Angles(0, 0, math.pi / 2)
			tweenPivot(tgt, tipCF, 0.55)
			burst(folder, tBase2.Position, Color3.fromRGB(120, 120, 120), 16, 10, 0.9)
			if tgt.hpBar and tgt.hpBar.gui then
				tgt.hpBar.gui.Enabled = false
			end
			task.spawn(function()
				for _, d in ipairs((tgt.model :: Model):GetDescendants()) do
					if d:IsA("BasePart") and d.Name ~= "RarityPlate" then
						TweenService:Create(d, TweenInfo.new(0.5), { Color = Color3.fromRGB(110, 110, 110) }):Play()
					end
				end
			end)
			damageNumber(folder, tgtPos + Vector3.new(0, 5.6, 0), "FAINTED", Color3.fromRGB(255, 90, 90), true)
			task.wait(0.7)
		elseif tgt and not tgt.fainted then
			tweenPivot(tgt, tgt.baseCF, 0.28)
			task.wait(0.3)
		end
	end

	if event.miss then
		tweenPivot(atk, CFrame.new(atkBase.Position + Vector3.new(atkDir * -1.2, -0.4, 0)) * rotOnly(atkBase), 0.18)
		task.wait(0.2)
		tweenPivot(atk, CFrame.new(atkBase.Position + Vector3.new(atkDir * 4, 0, 0)) * rotOnly(atkBase), 0.2)
		if tgt and not tgt.fainted then
			local tBase: CFrame = tgt.baseCF
			task.spawn(function()
				tweenPivot(tgt, CFrame.new(tBase.Position + Vector3.new(0, 1.4, 2.6)) * rotOnly(tBase), 0.18)
				task.wait(0.24)
				tweenPivot(tgt, tBase, 0.25)
			end)
		end
		task.wait(0.28)
		local missPos = if tgt then tgt.baseCF.Position else atkBase.Position
		damageNumber(folder, missPos + Vector3.new(0, 2.4, 0), "MISS", Color3.fromRGB(190, 190, 190), false)
		task.wait(0.35)
		tweenPivot(atk, atkBase, 0.3)
		task.wait(0.32)
	elseif kind == "blast" then
		tweenPivot(atk, CFrame.new(atkBase.Position + Vector3.new(0, 0.9, 0)) * rotOnly(atkBase), 0.25)
		task.wait(0.28)
		burst(folder, atkBase.Position + Vector3.new(0, 1.5, 0), fxColor, 10, 8, 0.6)
		if tgt then
			local toPos = tgt.baseCF.Position + Vector3.new(0, 0.8, 0)
			local fromPos = atkBase.Position + Vector3.new(0, 1.6, 0)
			local hitPos = fireProjectile(folder, fromPos, toPos, fxColor, (event.movePower or 0) >= 70)
			doImpact(hitPos, (event.movePower or 0) >= 70)
		else
			task.wait(0.4)
		end
		tweenPivot(atk, atkBase, 0.3)
		task.wait(0.32)
	else
		local big = kind == "heavy"
		tweenPivot(atk, CFrame.new(atkBase.Position + Vector3.new(atkDir * -1.4, -0.55, 0)) * rotOnly(atkBase), if big then 0.34 else 0.26)
		task.wait(if big then 0.36 else 0.28)
		if tgt then
			local tgtPos = tgt.baseCF.Position
			local toTgt = tgtPos - atkBase.Position
			local dist = math.sqrt(toTgt.X * toTgt.X + toTgt.Z * toTgt.Z)
			local dashDist = math.max(1, dist - 2.6)
			local dashPos = atkBase.Position + Vector3.new(toTgt.X / math.max(0.01, dist) * dashDist, 0, toTgt.Z / math.max(0.01, dist) * dashDist)
			tweenPivot(atk, CFrame.new(dashPos) * rotOnly(atkBase), 0.15)
			task.wait(0.17)
			doImpact(tgtPos + Vector3.new(0, 0.6, 0), big)
		else
			task.wait(0.4)
		end
		tweenPivot(atk, atkBase, 0.3)
		task.wait(0.32)
	end

	atk.frozen = false
	if tgt then
		tgt.frozen = false
	end
end

function PlotSystem.PlayBattleTurn(player: Player, events: any)
	if type(events) ~= "table" then
		return
	end
	for _, event in ipairs(events) do
		PlotSystem.PlayBattleEvent(player, event)
		task.wait(0.25)
	end
end

function PlotSystem.PlayVictory(player: Player, winnerSide: string)
	local rec = battleArenas[player.UserId]
	if not rec then
		return
	end
	local team = if winnerSide == "player" then rec.pModels else rec.eModels
	local folder = rec.folder
	local cx, cz = arenaCenterXZ()
	for _, h in ipairs(team) do
		if h and not h.fainted and h.model and h.model.Parent then
			h.frozen = true
			task.spawn(function()
				for _ = 1, 3 do
					if not h.model.Parent then
						break
					end
					local base: CFrame = h.baseCF
					tweenPivot(h, CFrame.new(base.Position + Vector3.new(0, 2.4, 0)) * rotOnly(base), 0.22)
					task.wait(0.26)
					if not h.model.Parent then
						break
					end
					tweenPivot(h, base, 0.22)
					task.wait(0.26)
				end
				h.frozen = false
			end)
		end
	end
	task.spawn(function()
		local colors = {
			Color3.fromRGB(255, 100, 100),
			Color3.fromRGB(100, 255, 100),
			Color3.fromRGB(100, 150, 255),
			Color3.fromRGB(255, 220, 80),
			Color3.fromRGB(200, 120, 255),
		}
		for i = 1, 6 do
			local pos = Vector3.new(cx + (math.random() - 0.5) * 18, arenaFloorTop() + 9, cz + (math.random() - 0.5) * 18)
			burst(folder, pos, colors[(i % #colors) + 1], 26, 16, 0.8)
			task.wait(0.28)
		end
	end)
	task.wait(2.4)
end

return PlotSystem
