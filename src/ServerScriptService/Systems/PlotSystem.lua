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
local PLOT_SIZE = 52
local PLOT_GAP = 80 -- lots of lawn between plots so bases do not crowd
-- WORLD OFFSET: shifts ALL gameplay (plots, obby, arena, fusion lab) to sit on
-- flat ground. Tune these if content is buried or floating on your terrain.
local WORLD_DX = 127
local WORLD_DZ = 98
-- Arena used to sit at (WORLD_DX, WORLD_DZ - 70), right against the plots.
-- +X is toward the river/mountain; left of the plots is -X, on the open grass.
local ARENA_X = WORLD_DX - 300
local ARENA_Z = WORLD_DZ - 260
local ARENA_SCALE = 4
local ARENA_PAD = 280
-- Fusion lab sits near the plaza boards, not on a player pad.
local FUSION_X = WORLD_DX
local FUSION_Z = WORLD_DZ + 12
-- One plaza row in front of the plots (west of plot 1, south lawn).
-- Order: Fusion, Stat Trainer (old expedition slot), Quests. Expeditions are portals.
local PLAZA_Z = 28
local PLAZA_GAP = 24
local PLAZA_X0 = 68
PlotSystem.PlazaSpots = {
	Fusion = Vector2.new(PLAZA_X0 + PLAZA_GAP, PLAZA_Z),
	Trainer = Vector2.new(PLAZA_X0 + PLAZA_GAP * 2, PLAZA_Z),
	Quest = Vector2.new(PLAZA_X0 + PLAZA_GAP * 3, PLAZA_Z),
}

function PlotSystem.SitOnTerrain(model: Model, x: number, z: number)
	model:PivotTo(CFrame.new(x, 0, z))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
	local gy = if hit then hit.Position.Y else 0
	local boxCF, boxSize = model:GetBoundingBox()
	local bottomY = boxCF.Position.Y - boxSize.Y * 0.5
	model:TranslateBy(Vector3.new(0, gy - bottomY, 0))
end

-- Plots are lined up side-by-side along X, all facing +Z (front = +Z).

local plotsFolder: Folder? = nil
local playerPlots: { [number]: Model } = {} -- [userId] -> plot

-- Stay just off the 52-stud plot slabs, and do not wander 200 studs into the hills.
function PlotSystem.PickClearSpot(preferX: number, preferZ: number, extras: { Vector2 }?): (number, number)
	local plotClear = 34
	local extraClear = 24
	local function blocked(x: number, z: number): boolean
		if plotsFolder then
			for _, plot in ipairs(plotsFolder:GetChildren()) do
				local base = plot:FindFirstChild("Base")
				if base and base:IsA("BasePart") then
					local dx = x - (base :: BasePart).Position.X
					local dz = z - (base :: BasePart).Position.Z
					if math.abs(dx) < plotClear and math.abs(dz) < plotClear then
						return true
					end
				end
			end
		end
		if extras then
			for _, p in ipairs(extras) do
				local dx = x - p.X
				local dz = z - p.Y
				if dx * dx + dz * dz < extraClear * extraClear then
					return true
				end
			end
		end
		return false
	end
	if not blocked(preferX, preferZ) then
		return preferX, preferZ
	end
	for r = 8, 56, 8 do
		for a = 0, 15 do
			local x = preferX + math.cos(a * math.pi / 8) * r
			local z = preferZ + math.sin(a * math.pi / 8) * r
			if not blocked(x, z) then
				return x, z
			end
		end
	end
	return preferX, preferZ
end

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
-- Snap a model's bounding-box bottom-center onto the target's top-center.
local function bboxSizeOf(model: Model): Vector3
	local ok, _, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and size then
		return size
	end
	return Vector3.new(1, 1, 1)
end

-- Store the extra tilt so wander lookAt CFrames do not flatten pack meshes.
function PlotSystem.RememberStand(model: Model)
	local p = model:GetPivot()
	local flatLook = Vector3.new(p.LookVector.X, 0, p.LookVector.Z)
	if flatLook.Magnitude < 0.08 then
		flatLook = Vector3.new(0, 0, -1)
	else
		flatLook = flatLook.Unit
	end
	local yaw = CFrame.lookAt(Vector3.zero, flatLook, Vector3.yAxis)
	local existing = model:FindFirstChild("StandRotation")
	if existing then
		existing:Destroy()
	end
	local v = Instance.new("CFrameValue")
	v.Name = "StandRotation"
	v.Value = yaw:Inverse() * (p - p.Position)
	v.Parent = model
end

function PlotSystem.FacingCFrame(model: Model, pos: Vector3, dir: Vector3): CFrame
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.05 then
		flat = Vector3.new(0, 0, -1)
	else
		flat = flat.Unit
	end
	local stand = CFrame.new()
	local v = model:FindFirstChild("StandRotation")
	if v and v:IsA("CFrameValue") then
		stand = (v :: CFrameValue).Value
	end
	return CFrame.new(pos) * CFrame.lookAt(Vector3.zero, flat, Vector3.yAxis) * stand
end

local extraUprightFlip: (Model) -> () = function(_model: Model) end

-- Long animals (Ganganzelli) stay long on the ground: roll around the long axis
-- until height is max. Sticks (Tung Tung) then stand longest-axis-up.
-- 180° feet-vs-head is extraUprightFlip, not this.
local function uprightModel(model: Model)
	local start = model:GetPivot()
	local size = bboxSizeOf(model)
	local yIsLongest = size.Y + 0.05 >= size.X and size.Y + 0.05 >= size.Z
	if not yIsLongest then
		local options: { CFrame }
		if size.X >= size.Z then
			options = {
				start,
				start * CFrame.Angles(math.pi / 2, 0, 0),
				start * CFrame.Angles(math.pi, 0, 0),
				start * CFrame.Angles(-math.pi / 2, 0, 0),
			}
		else
			options = {
				start,
				start * CFrame.Angles(0, 0, math.pi / 2),
				start * CFrame.Angles(0, 0, math.pi),
				start * CFrame.Angles(0, 0, -math.pi / 2),
			}
		end
		local bestCF = start
		local bestY = size.Y
		for _, cf in ipairs(options) do
			model:PivotTo(cf)
			local s = bboxSizeOf(model)
			if s.Y > bestY + 0.05 then
				bestY = s.Y
				bestCF = cf
			end
		end
		model:PivotTo(bestCF)
	end

	size = bboxSizeOf(model)
	local maxD = math.max(size.X, size.Y, size.Z)
	local minD = math.min(size.X, size.Y, size.Z)
	local midD = size.X + size.Y + size.Z - maxD - minD
	local roundCross = midD <= minD * 1.35
	if roundCross and maxD > midD * 1.45 and size.Y + 0.08 < maxD then
		local pivot = model:GetPivot()
		local options: { CFrame }
		if size.X >= size.Z then
			options = {
				pivot * CFrame.Angles(0, 0, math.pi / 2),
				pivot * CFrame.Angles(0, 0, -math.pi / 2),
			}
		else
			options = {
				pivot * CFrame.Angles(math.pi / 2, 0, 0),
				pivot * CFrame.Angles(-math.pi / 2, 0, 0),
			}
		end
		local bestCF = options[1]
		local bestY = -1
		for _, cf in ipairs(options) do
			model:PivotTo(cf)
			local s = bboxSizeOf(model)
			if s.Y > bestY then
				bestY = s.Y
				bestCF = cf
			end
		end
		model:PivotTo(bestCF)
	end
	extraUprightFlip(model)
	PlotSystem.RememberStand(model)
end

local MAX_DISPLAY_SIZE = 4.2

local function modelMaxDim(model: Model): number
	local maxDim = 0
	local ok, _, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and size then
		maxDim = math.max(size.X, size.Y, size.Z)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local part = d :: BasePart
			maxDim = math.max(maxDim, part.Size.X, part.Size.Y, part.Size.Z)
		end
	end
	pcall(function()
		local e = model:GetExtentsSize()
		maxDim = math.max(maxDim, e.X, e.Y, e.Z)
	end)
	return maxDim
end

local function shrinkToPedestalSize(model: Model)
	uprightModel(model)
	for _ = 1, 5 do
		local maxDim = modelMaxDim(model)
		if maxDim <= MAX_DISPLAY_SIZE or maxDim < 0.05 then
			return
		end
		local s = math.clamp(MAX_DISPLAY_SIZE / maxDim, 0.02, 1)
		local before = maxDim
		pcall(function()
			model:ScaleTo(s)
		end)
		local after = modelMaxDim(model)
		if math.abs(after - before) < (before * 0.05) then
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") then
					local part = d :: BasePart
					part.Size = part.Size * s
					part.Position = part.Position * s
					for _, m in ipairs(part:GetChildren()) do
						if m:IsA("SpecialMesh") then
							(m :: SpecialMesh).Scale = (m :: SpecialMesh).Scale * s
						elseif m:IsA("DataModelMesh") then
							(m :: DataModelMesh).Scale = (m :: DataModelMesh).Scale * s
						end
					end
				end
			end
		end
	end
end

local function placeModelOnTop(model: Model, targetPart: BasePart, extraOffset: number)
	if model.Parent then
		PlotSystem.FitInWorld(model, MAX_DISPLAY_SIZE)
	else
		shrinkToPedestalSize(model)
	end
	uprightModel(model)
	local cf, size = model:GetBoundingBox()
	local lift = extraOffset
	local target = Vector3.new(
		targetPart.Position.X,
		targetPart.Position.Y + targetPart.Size.Y / 2 + lift,
		targetPart.Position.Z
	)
	local currentBottom = Vector3.new(cf.Position.X, cf.Position.Y - size.Y / 2, cf.Position.Z)
	model:PivotTo(model:GetPivot() + (target - currentBottom))
end

function PlotSystem.UprightModel(model: Model)
	uprightModel(model)
end

local function hasFileMeshAsset(model: Model): boolean
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SpecialMesh") or d:IsA("FileMesh") then
			local mesh = d :: FileMesh
			if mesh.MeshId ~= "" then
				return true
			end
		end
	end
	return false
end

-- Server does not load MeshId geometry, so GetExtentsSize stays tiny while
-- the client renders a giant. Scale those down by a fixed factor.
local function fitLyingFileMesh(model: Model, maxSize: number)
	if not hasFileMeshAsset(model) then
		return
	end
	local maxDim = modelMaxDim(model)
	if maxDim > maxSize * 0.85 then
		return
	end
	local factor = maxSize / 150
	pcall(function()
		model:ScaleTo(model:GetScale() * factor)
	end)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("SpecialMesh") or d:IsA("FileMesh") or d:IsA("DataModelMesh") then
			(d :: DataModelMesh).Scale = (d :: DataModelMesh).Scale * factor
		end
	end
	model:SetAttribute("FileMeshFit", true)
	print("[PlotSystem] force-fit " .. model.Name .. " x" .. string.format("%.3f", factor))
end

extraUprightFlip = function(model: Model)
	if not hasFileMeshAsset(model) then
		return
	end
	if model:GetAttribute("UprightFlipped") == true then
		return
	end
	local id = model:GetAttribute("BrainrotId")
	local catalogFlip = false
	if typeof(id) == "string" then
		local flips = BrainrotData.FLIP_UPSIDE_DOWN
		catalogFlip = flips[id] == true
		local def = BrainrotData.GetById(id)
		if def and def.Display and def.Display.FlipUpsideDown == true then
			catalogFlip = true
		end
	end
	local function doFlip()
		model:PivotTo(model:GetPivot() * CFrame.Angles(math.pi, 0, 0))
		model:SetAttribute("UprightFlipped", true)
	end
	if catalogFlip then
		doFlip()
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if part and part.CFrame.UpVector.Y < -0.35 then
		doFlip()
		return
	end
	local ok, bbCF, bbSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if ok and bbCF and bbSize and (bbSize :: Vector3).Y >= 0.5 then
		local pivotY = model:GetPivot().Position.Y
		local midY = (bbCF :: CFrame).Position.Y
		if pivotY > midY + (bbSize :: Vector3).Y * 0.08 then
			doFlip()
		end
	end
end

-- Live pack meshes ignore Model:ScaleTo; their size is FileMesh.Scale.
-- Studio already has a real bbox, so ScaleTo is enough there.
function PlotSystem.ApplyWildSize(model: Model, mult: number)
	if model:GetAttribute("FileMeshFit") == true then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("SpecialMesh") or d:IsA("FileMesh") or d:IsA("DataModelMesh") then
				(d :: DataModelMesh).Scale = (d :: DataModelMesh).Scale * mult
			end
		end
		print("[PlotSystem] wild FileMesh x" .. tostring(mult) .. " " .. model.Name)
		return
	end
	pcall(function()
		model:ScaleTo(model:GetScale() * mult)
	end)
	print("[PlotSystem] wild ScaleTo x" .. tostring(mult) .. " " .. model.Name)
end

-- Call after the model is in Workspace. Pack meshes often report a tiny
-- bounding box until then, which made Chillin Chili / Tralalero grow.
function PlotSystem.FitInWorld(model: Model, maxSize: number)
	if not model.Parent then
		model.Parent = workspace
	end
	uprightModel(model)
	local maxDim = modelMaxDim(model)
	if maxDim > maxSize and maxDim >= 0.05 then
		local s = math.clamp(maxSize / maxDim, 0.01, 1)
		pcall(function()
			model:ScaleTo(model:GetScale() * s)
		end)
	end
	fitLyingFileMesh(model, maxSize)
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
	local function importChild(child: Instance, variantId: string?)
		if not (child:IsA("Model") or child:IsA("Folder") or child:IsA("BasePart")) then
			return
		end
		local id = packNameToId(child.Name)
		if not id then
			return
		end
		matched += 1
		local storeName = if variantId then (id .. "__" .. variantId) else id
		if modelsFolder:FindFirstChild(storeName) then
			return
		end
		local copy = child:Clone()
		for _, d in ipairs(copy:GetDescendants()) do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("ModuleScript")
				or d:IsA("BillboardGui") or d:IsA("SurfaceGui") then
				d:Destroy()
			end
		end
		copy.Name = storeName
		copy.Parent = modelsFolder
	end

	local packFolders = BrainrotData.PACK_FOLDERS
	local importedFromFolders = false
	for _, child in ipairs(pack:GetChildren()) do
		local key = string.lower(child.Name):gsub("ó", "o")
		if packFolders[key] ~= nil or key == "normal" then
			if child:IsA("Folder") or child:IsA("Model") then
				importedFromFolders = true
				local variantId = packFolders[key]
				for _, model in ipairs(child:GetChildren()) do
					importChild(model, variantId)
				end
			end
		end
	end
	if not importedFromFolders then
		for _, child in ipairs(pack:GetChildren()) do
			importChild(child, nil)
		end
	end

	if matched > 0 then
		pcall(function()
			pack:Destroy()
		end)
	end
end

-- // Plot construction ----------------------------------------------------------
print("[PlotSystem] source 30-upright")

function PlotSystem.SetArenaBoardText(text: string)
	local labels = PlotSystem.ArenaBoardLabels
	if type(labels) == "table" then
		for _, label in ipairs(labels) do
			if label and label:IsA("TextLabel") then
				(label :: TextLabel).Text = text
			end
		end
	end
	local one = PlotSystem.ArenaBoardLabel
	if one and one:IsA("TextLabel") then
		(one :: TextLabel).Text = text
	end
end

function PlotSystem.Setup()
	print("[PlotSystem] Loaded placement v30-upright")
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

	local function flattenPad(cx: number, cz: number, topY: number, padSize: number?)
		local pad = padSize or (PLOT_SIZE + 18)
		local thickness = math.max(20, topY + 12)
		pcall(function()
			workspace.Terrain:FillBlock(
				CFrame.new(cx, topY - thickness / 2, cz),
				Vector3.new(pad, thickness, pad),
				Enum.Material.Air
			)
		end)
	end

	local function minGroundY(cx: number, cz: number, half: number): number
		local m = groundY(cx, cz)
		for _, ox in ipairs({ -half, half }) do
			for _, oz in ipairs({ -half, half }) do
				local h = groundY(cx + ox, cz + oz)
				if h < m then m = h end
			end
		end
		return m
	end

	-- Solid flat plateau so the arena does not float over an air pit.
	local function fillSolidPad(cx: number, cz: number, topY: number, padSize: number, lowY: number)
		local bottom = math.min(lowY, topY) - 28
		local height = (topY - bottom) + 2
		pcall(function()
			workspace.Terrain:FillBlock(
				CFrame.new(cx, bottom + height / 2, cz),
				Vector3.new(padSize, height, padSize),
				Enum.Material.Concrete
			)
		end)
	end

	local existing = workspace:FindFirstChild("Plots")
	if existing then
		existing:Destroy()
	end
	plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = workspace

	local limit = BrainrotData.SHOWCASE_LIMIT
	local perRow = 5

	local function measurePatch(cx: number, cz: number): any
		local half = PLOT_SIZE / 2
		local minY, maxY = math.huge, -math.huge
		local waterHits = 0
		local samples = 0
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		for ox = -half, half, 10 do
			for oz = -half, half, 10 do
				local r = workspace:Raycast(Vector3.new(cx + ox, 800, cz + oz), Vector3.new(0, -1600, 0), params)
				if not r then
					return nil
				end
				samples += 1
				if r.Material == Enum.Material.Water then
					waterHits += 1
				end
				if r.Position.Y < minY then
					minY = r.Position.Y
				end
				if r.Position.Y > maxY then
					maxY = r.Position.Y
				end
			end
		end
		if samples < 8 or waterHits > samples * 0.12 then
			return nil
		end
		return {
			X = cx,
			Z = cz,
			Y = maxY,
			Range = maxY - minY,
		}
	end

	local function farEnough(x: number, z: number, chosen: { any }): boolean
		local minSep = PLOT_SIZE + PLOT_GAP * 0.75
		for _, site in ipairs(chosen) do
			local dx = x - site.X
			local dz = z - site.Z
			if (dx * dx + dz * dz) < (minSep * minSep) then
				return false
			end
		end
		return true
	end

	local candidates: { any } = {}
	local searchHalf = 400
	local step = 28
	for cx = WORLD_DX - searchHalf, WORLD_DX + searchHalf, step do
		for cz = WORLD_DZ - searchHalf, WORLD_DZ + searchHalf, step do
			local dx = cx - WORLD_DX
			local dz = cz - WORLD_DZ
			if (dx * dx + dz * dz) >= (55 * 55) then
				local patch = measurePatch(cx, cz)
				if patch and patch.Range <= 3.5 then
					table.insert(candidates, patch)
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		if math.abs(a.Range - b.Range) > 0.4 then
			return a.Range < b.Range
		end
		local da = (a.X - WORLD_DX) * (a.X - WORLD_DX) + (a.Z - WORLD_DZ) * (a.Z - WORLD_DZ)
		local db = (b.X - WORLD_DX) * (b.X - WORLD_DX) + (b.Z - WORLD_DZ) * (b.Z - WORLD_DZ)
		return da < db
	end)

	local sites: { any } = {}
	for _, patch in ipairs(candidates) do
		if #sites >= PLOT_COUNT then
			break
		end
		if farEnough(patch.X, patch.Z, sites) then
			table.insert(sites, patch)
		end
	end
	-- Fallback: original grid, each plot still sits on its own ground height.
	if #sites < PLOT_COUNT then
		local PLOT_COLS = 3
		local rowsTotal = math.ceil(PLOT_COUNT / PLOT_COLS)
		for i = 1, PLOT_COUNT do
			if not sites[i] then
				local col = (i - 1) % PLOT_COLS
				local row = math.floor((i - 1) / PLOT_COLS)
				local x = (col - (PLOT_COLS - 1) / 2) * (PLOT_SIZE + PLOT_GAP) + WORLD_DX
				local z = (row - (rowsTotal - 1) / 2) * (PLOT_SIZE + PLOT_GAP) + WORLD_DZ
				local h = maxGroundY(x, z, PLOT_SIZE / 2)
				sites[i] = { X = x, Z = z, Y = h, Range = 99 }
			end
		end
	end

	for i = 1, PLOT_COUNT do
		local site = sites[i]
		local x, z = site.X, site.Z
		print("[PlotSystem] Plot " .. tostring(i) .. " on terrain at " .. tostring(Vector3.new(x, site.Y, z)) .. " (uneven " .. string.format("%.1f", site.Range) .. ")")

		local plot = Instance.new("Model")
		plot.Name = "Plot" .. i
		plot:SetAttribute("Index", i)

		newPart({
			Name = "GroundSlab",
			Size = Vector3.new(PLOT_SIZE + 16, 8, PLOT_SIZE + 16),
			Position = Vector3.new(x, -3.9, z),
			Anchored = true,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(110, 110, 118),
		}, plot)
		newPart({
			Name = "BaseBorder",
			Size = Vector3.new(PLOT_SIZE + 2, 1, PLOT_SIZE + 2),
			Position = Vector3.new(x, 0.4, z),
			Anchored = true,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(120, 120, 130),
		}, plot)
		newPart({
			Name = "Base",
			Size = Vector3.new(PLOT_SIZE, 1, PLOT_SIZE),
			Position = Vector3.new(x, 0.6, z),
			Anchored = true,
			Material = Enum.Material.SmoothPlastic,
			Color = Color3.fromRGB(95, 180, 95),
		}, plot)
		local deckY = 8
		local deckDepth = PLOT_SIZE * 0.55
		local deckCenterZ = z - PLOT_SIZE * 0.22
		local deckBackZ = deckCenterZ + deckDepth / 2
		local deckFrontZ = deckCenterZ - deckDepth / 2
		for _, cx in ipairs({ -1, 1 }) do
			for _, cz in ipairs({ -1, 1 }) do
				newPart({
					Name = "CornerPost",
					Size = Vector3.new(1.2, deckY + 1, 1.2),
					Position = Vector3.new(
						x + cx * (PLOT_SIZE / 2 - 0.6),
						(deckY + 1) / 2,
						z + cz * (PLOT_SIZE / 2 - 0.6)
					),
					Anchored = true,
					Material = Enum.Material.Wood,
					Color = Color3.fromRGB(140, 100, 60),
				}, plot)
			end
		end

		-- Showcase lives on the upper deck; work stays on the grass below.
		newPart({
			Name = "UpperDeck",
			Size = Vector3.new(PLOT_SIZE - 2, 1, deckDepth),
			Position = Vector3.new(x, deckY, deckCenterZ),
			Anchored = true,
			Material = Enum.Material.WoodPlanks,
			Color = Color3.fromRGB(150, 115, 80),
		}, plot)
		newPart({
			Name = "DeckRailFront",
			Size = Vector3.new(PLOT_SIZE - 2, 1.2, 0.4),
			Position = Vector3.new(x, deckY + 1.1, deckFrontZ),
			Anchored = true,
			Material = Enum.Material.Wood,
			Color = Color3.fromRGB(120, 85, 55),
		}, plot)
		local stairCount = 8
		local stepDepth = 2.5
		local stairX = x + PLOT_SIZE / 2 - 3
		for step = 1, stairCount do
			-- Last step shares the deck's back edge (same height, no gap).
			local stairZ = deckBackZ + (stairCount - step) * stepDepth + stepDepth / 2
			newPart({
				Name = "Stair_" .. step,
				Size = Vector3.new(6, 1, stepDepth),
				Position = Vector3.new(stairX, (deckY / stairCount) * step, stairZ),
				Anchored = true,
				Material = Enum.Material.Wood,
				Color = Color3.fromRGB(160, 130, 90),
			}, plot)
		end

		local sign = newPart({
			Name = "OwnerSign",
			Size = Vector3.new(8, 4, 0.6),
			Position = Vector3.new(x, deckY + 3, deckFrontZ + 0.8),
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
			local px = x - 16 + col * 8
			local pz = deckCenterZ - 6 + row * 8
			newPart({
				Name = "Pedestal_" .. slot,
				Size = Vector3.new(3, 1.2, 3),
				Position = Vector3.new(px, deckY + 1.1, pz),
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
			local sx = x - 16 + (sIdx - 1) * 8
			local sz = z + PLOT_SIZE / 2 - 6

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
		local topY = maxGroundY(x, z, PLOT_SIZE / 2)
		flattenPad(x, z, topY)
		liftModel(plot, topY + 0.4)
	end

	local plaza = Instance.new("Folder")
	plaza.Name = "Plaza"
	plaza.Parent = workspace

	local FUSION_PLACE_X = PlotSystem.PlazaSpots.Fusion.X
	local FUSION_PLACE_Z = PlotSystem.PlazaSpots.Fusion.Y
	PlotSystem.FusionXZ = Vector2.new(FUSION_PLACE_X, FUSION_PLACE_Z)

	local lab: Model
	local customFusion = ReplicatedStorage:FindFirstChild("FusionMachine") or ReplicatedStorage:FindFirstChild("FusionLabModel")
	if customFusion and customFusion:IsA("Model") then
		lab = (customFusion :: Model):Clone()
		lab.Name = "FusionLab"
	else
		lab = VisualEffects.BuildFusionMachine()
	end
	lab.Parent = plaza
	PlotSystem.SitOnTerrain(lab, FUSION_PLACE_X, FUSION_PLACE_Z)
	local labPromptInst = lab:FindFirstChild("FusionPrompt", true)
	if not (labPromptInst and labPromptInst:IsA("ProximityPrompt")) then
		local attach = lab.PrimaryPart or lab:FindFirstChildWhichIsA("BasePart")
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "FusionPrompt"
		prompt.ActionText = "Open Fusion Lab"
		prompt.ObjectText = "Fusion Reactor"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 16
		prompt.RequiresLineOfSight = false
		prompt.Parent = attach
		labPromptInst = prompt
	end
	PlotSystem.FusionPrompt = labPromptInst :: ProximityPrompt

	local arena = Instance.new("Model")
	arena.Name = "Arena"
	local s = ARENA_SCALE
	-- Use the hill under the arena, not a neighboring cliff, as the floor height.
	local arenaTopY = groundY(ARENA_X, ARENA_Z)
	local arenaLowY = minGroundY(ARENA_X, ARENA_Z, ARENA_PAD / 2)
	fillSolidPad(ARENA_X, ARENA_Z, arenaTopY, ARENA_PAD, arenaLowY)
	newPart({
		Name = "GroundSlab",
		Size = Vector3.new(ARENA_PAD, 8, ARENA_PAD),
		Position = Vector3.new(ARENA_X, -3.9, ARENA_Z),
		Anchored = true,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(110, 110, 118),
	}, arena)
	newPart({
		Name = "Floor",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(44 * s, 2, 44 * s),
		Position = Vector3.new(ARENA_X, 1, ARENA_Z),
		Anchored = true,
		Color = Color3.fromRGB(200, 170, 120),
		Material = Enum.Material.Sand,
	}, arena)
	newPart({
		Name = "Center",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(12 * s, 2.4, 12 * s),
		Position = Vector3.new(ARENA_X, 1.2, ARENA_Z),
		Anchored = true,
		Color = Color3.fromRGB(180, 60, 60),
		Material = Enum.Material.SmoothPlastic,
	}, arena)
	for _, side in ipairs({ -1, 1 }) do
		newPart({
			Name = "Gate" .. if side < 0 then "Blue" else "Red",
			Size = Vector3.new(6 * s, 8 * s, 1 * s),
			Position = Vector3.new(ARENA_X + side * 16 * s, 5 * s, ARENA_Z),
			Anchored = true,
			Color = if side < 0 then Color3.fromRGB(60, 120, 220) else Color3.fromRGB(220, 60, 60),
			Material = Enum.Material.SmoothPlastic,
		}, arena)
	end
	arena.Parent = plaza
	liftModel(arena, arenaTopY + 0.4)

	local function sitOnLocalGround(part: BasePart, x: number, z: number, extra: number)
		local gy = math.max(groundY(x, z), arenaTopY)
		part.Position = Vector3.new(x, gy + part.Size.Y * 0.5 + extra, z)
	end

	-- Outside the colosseum, sitting on the hillside (not the arena-center height).
	local arenaSign = newPart({
		Name = "Sign",
		Size = Vector3.new(16, 5.2, 1),
		Position = Vector3.new(ARENA_X - 22, arenaTopY + 8, ARENA_Z + 30 * s + 14),
		Anchored = true,
		Color = Color3.fromRGB(90, 70, 50),
		Material = Enum.Material.Wood,
	}, plaza)
	sitOnLocalGround(arenaSign, ARENA_X - 22, ARENA_Z + 30 * s + 14, 0.6)
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
	local arenaGuiFront = Instance.new("SurfaceGui")
	arenaGuiFront.Face = Enum.NormalId.Front
	arenaGuiFront.Parent = arenaSign
	local arenaLabelFront = arenaLabel:Clone()
	arenaLabelFront.Parent = arenaGuiFront
	local arenaPrompt = Instance.new("ProximityPrompt")
	arenaPrompt.Name = "ArenaPrompt"
	arenaPrompt.ActionText = "Enter Arena"
	arenaPrompt.ObjectText = "Arena"
	arenaPrompt.HoldDuration = 0
	arenaPrompt.MaxActivationDistance = 36
	arenaPrompt.RequiresLineOfSight = false
	arenaPrompt.Parent = arenaSign
	PlotSystem.ArenaPrompt = arenaPrompt

	local arenaCenter = Vector3.new(ARENA_X, arenaTopY + 1, ARENA_Z)
	local colosseum = VisualEffects.BuildColosseum(arenaCenter, ARENA_SCALE)
	colosseum.Parent = plaza

	local labels: { TextLabel } = {}
	local function addBoardFace(part: BasePart, face: Enum.NormalId, title: boolean): TextLabel
		local gui = Instance.new("SurfaceGui")
		gui.Face = face
		gui.PixelsPerStud = 25
		gui.LightInfluence = 0
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Name = if title then "TitleText" else "RankText"
		label.Size = UDim2.new(1, -24, 1, -24)
		label.Position = UDim2.new(0, 12, 0, 12)
		label.BackgroundTransparency = 1
		label.Text = if title then "ARENA CHAMPIONS" else "No wins yet — beat a rival!"
		label.Font = Enum.Font.GothamBold
		label.TextScaled = title
		label.TextSize = 28
		label.TextColor3 = Color3.fromRGB(255, 220, 120)
		label.TextStrokeTransparency = 0.3
		label.TextWrapped = true
		label.TextYAlignment = if title then Enum.TextYAlignment.Center else Enum.TextYAlignment.Top
		label.Parent = gui
		if not title then
			table.insert(labels, label)
		end
		return label
	end

	-- Outside the colosseum on the same face as the ARENA sign (player approach).
	local wallR = 30 * s
	local boardX = ARENA_X
	local boardZ = ARENA_Z + wallR + 18
	local frame = newPart({
		Name = "ChampionBoard",
		Size = Vector3.new(28, 20, 1.2),
		Position = Vector3.new(boardX, arenaTopY + 12, boardZ),
		Anchored = true,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(22, 18, 14),
	}, plaza)
	sitOnLocalGround(frame, boardX, boardZ, 0.6)
	local header = newPart({
		Name = "ChampionHeader",
		Size = Vector3.new(28, 3.2, 1.2),
		Position = Vector3.new(boardX, frame.Position.Y + frame.Size.Y * 0.5 + 1.8, boardZ),
		Anchored = true,
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(40, 28, 12),
	}, plaza)
	addBoardFace(header, Enum.NormalId.Front, true)
	addBoardFace(header, Enum.NormalId.Back, true)
	addBoardFace(frame, Enum.NormalId.Front, false)
	addBoardFace(frame, Enum.NormalId.Back, false)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "LeaderboardBeacon"
	billboard.Size = UDim2.new(10, 0, 1.6, 0)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.MaxDistance = 110
	billboard.AlwaysOnTop = false
	billboard.Parent = header
	local beaconText = Instance.new("TextLabel")
	beaconText.Size = UDim2.new(1, 0, 1, 0)
	beaconText.BackgroundTransparency = 1
	beaconText.Text = "LEADERBOARD"
	beaconText.Font = Enum.Font.GothamBlack
	beaconText.TextScaled = true
	beaconText.TextColor3 = Color3.fromRGB(255, 230, 120)
	beaconText.TextStrokeTransparency = 0.35
	beaconText.Parent = billboard

	PlotSystem.ArenaBoardLabels = labels
	PlotSystem.ArenaBoardLabel = labels[1]
	local boardPrompt = Instance.new("ProximityPrompt")
	boardPrompt.Name = "BoardPrompt"
	boardPrompt.ActionText = "Read Champions"
	boardPrompt.ObjectText = "Leaderboard"
	boardPrompt.HoldDuration = 0
	boardPrompt.MaxActivationDistance = 40
	boardPrompt.RequiresLineOfSight = false
	boardPrompt.Parent = frame
	PlotSystem.ArenaBoardPrompt = boardPrompt
	print("[PlotSystem] ChampionBoard at", frame.Position)

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
			CanTouch = true,
		}, parent)
		coin:SetAttribute("Value", value)
		coin:SetAttribute("Collected", false)

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
			local respawn = math.clamp(20 + math.floor(value / 8), 25, 90)
			task.delay(respawn, function()
				if coin and coin.Parent then
					coin:SetAttribute("Collected", false)
					coin.Transparency = 0
				end
			end)
		end)

		return coin
	end

	task.spawn(function()
		while true do
			task.wait(0.08)
			local coinsFolder = workspace:FindFirstChild("CoinObby")
			local sky = workspace:FindFirstChild("SkyGold")
			for _, root in ipairs({ coinsFolder, sky }) do
				if root then
					local folder = root:FindFirstChild("Coins") or root
					for _, d in ipairs(folder:GetDescendants()) do
						if d:IsA("BasePart") and d.Name == "Coin" and not d:GetAttribute("Collected") then
							d.CFrame = d.CFrame * CFrame.Angles(0, 0.35, 0)
						end
					end
				end
			end
		end
	end)

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

	local sky = Instance.new("Model")
	sky.Name = "SkyGold"
	local skyCoins = Instance.new("Folder")
	skyCoins.Name = "Coins"
	skyCoins.Parent = sky

	local function nearBusy(x: number, z: number): boolean
		if math.abs(x - ARENA_X) < 170 and math.abs(z - ARENA_Z) < 170 then
			return true
		end
		if not plotsFolder then
			return false
		end
		for _, plot in ipairs(plotsFolder:GetChildren()) do
			local base = plot:FindFirstChild("Base")
			if base and base:IsA("BasePart") then
				local dx = x - (base :: BasePart).Position.X
				local dz = z - (base :: BasePart).Position.Z
				if math.abs(dx) < 40 and math.abs(dz) < 40 then
					return true
				end
			end
		end
		return false
	end

	local function goldValue(height: number): number
		return math.clamp(math.floor(10 + (math.max(0, height) / 9) ^ 1.22 * 5.2), 10, 280)
	end

	local function padTint(height: number): Color3
		if height > 190 then
			return Color3.fromRGB(255, 90, 210)
		elseif height > 130 then
			return Color3.fromRGB(255, 175, 40)
		elseif height > 70 then
			return Color3.fromRGB(220, 170, 55)
		end
		return Color3.fromRGB(150, 105, 45)
	end

	local padCount = 0
	local function addSkyPad(x: number, y: number, z: number, size: number, ground: number)
		padCount += 1
		local height = y - ground
		local plat = newPart({
			Name = "SkyPad_" .. padCount,
			Size = Vector3.new(size, 1, size),
			Position = Vector3.new(x, y, z),
			Anchored = true,
			Color = padTint(height),
			Material = if height > 130 then Enum.Material.Neon else Enum.Material.SmoothPlastic,
		}, sky)
		local value = goldValue(height)
		makeCoin(skyCoins, Vector3.new(x, y + 2.1, z), value)
		if height > 90 and padCount % 4 == 0 then
			newPart({
				Name = "Nugget",
				Shape = Enum.PartType.Ball,
				Size = Vector3.new(1.1, 1.1, 1.1),
				Position = Vector3.new(x + size * 0.28, y + 1.4, z),
				Anchored = true,
				CanCollide = false,
				Color = Color3.fromRGB(255, 210, 50),
				Material = Enum.Material.Neon,
			}, sky)
		end
		return plat
	end

	local seed = 91
	local function rnd(): number
		seed = (seed * 1664525 + 1013904223) % 4294967296
		return seed / 4294967296
	end

	local starts: { any } = {}
	local function tryStart(x: number, z: number)
		if nearBusy(x, z) then
			return
		end
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { workspace.Terrain }
		local hit = workspace:Raycast(Vector3.new(x, 500, z), Vector3.new(0, -1000, 0), params)
		if not hit or hit.Material == Enum.Material.Water then
			return
		end
		table.insert(starts, { X = x, Z = z, Y = hit.Position.Y })
	end

	for i = 1, 16 do
		local ang = (i / 16) * math.pi * 2 + 0.35
		local r = 85 + (i % 4) * 48
		tryStart(WORLD_DX + math.cos(ang) * r, WORLD_DZ + math.sin(ang) * r)
	end
	for i = 1, 8 do
		local ang = i * 0.85 + 1.1
		tryStart(WORLD_DX + math.cos(ang) * 230, WORLD_DZ + math.sin(ang) * 230)
	end

	local tips: { any } = {}
	for t, start in ipairs(starts) do
		local x, z = start.X, start.Z
		local y = start.Y + 3.2
		local dir = t * 0.73
		addSkyPad(x, y, z, 6.2, start.Y)
		if t <= 4 then
			local sign = newPart({
				Name = "SkySign",
				Size = Vector3.new(10, 4, 0.5),
				Position = Vector3.new(x, y + 4.2, z - 4),
				Anchored = true,
				Color = Color3.fromRGB(90, 60, 25),
				Material = Enum.Material.Wood,
			}, sky)
			local gui = Instance.new("SurfaceGui")
			gui.Face = Enum.NormalId.Front
			gui.Parent = sign
			local label = Instance.new("TextLabel")
			label.Size = UDim2.new(1, 0, 1, 0)
			label.BackgroundTransparency = 1
			label.Text = "SKY GOLD\nHigher = richer\nFall = start over"
			label.Font = Enum.Font.GothamBold
			label.TextScaled = true
			label.TextColor3 = Color3.fromRGB(255, 220, 80)
			label.Parent = gui
		end
		local steps = 24
		for n = 1, steps do
			dir += 0.42 + rnd() * 0.5
			local dist = 9.2 + rnd() * 3.6
			x += math.cos(dir) * dist
			z += math.sin(dir) * dist
			y += 6.3 + rnd() * 1.6
			local height = y - start.Y
			local size = math.max(2.35, 5.5 - height / 85)
			addSkyPad(x, y, z, size, start.Y)
		end
		table.insert(tips, { X = x, Y = y, Z = z, Ground = start.Y })
	end

	for i, a in ipairs(tips) do
		for j = i + 1, #tips do
			local b = tips[j]
			local dx, dz = b.X - a.X, b.Z - a.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist > 18 and dist < 70 then
				local steps = math.max(2, math.floor(dist / 12))
				for s = 1, steps - 1 do
					local u = s / steps
					addSkyPad(a.X + dx * u, (a.Y + b.Y) * 0.5 + 2, a.Z + dz * u, 3.2, math.min(a.Ground, b.Ground))
				end
			end
		end
	end

	if #tips > 0 then
		table.sort(tips, function(a, b)
			return a.Y > b.Y
		end)
		local peak = tips[1]
		local peakY = peak.Y + 14
		addSkyPad(peak.X, peakY, peak.Z, 7.5, peak.Ground)
		local jackpot = newPart({
			Name = "Jackpot",
			Size = Vector3.new(8, 1.2, 8),
			Position = Vector3.new(peak.X, peakY + 0.8, peak.Z),
			Anchored = true,
			Color = Color3.fromRGB(255, 220, 40),
			Material = Enum.Material.Neon,
		}, sky)
		makeCoin(skyCoins, Vector3.new(peak.X, peakY + 3.2, peak.Z), 400)
		local lastJack: { [number]: number } = {}
		jackpot.Touched:Connect(function(hit: BasePart)
			local char = hit and hit.Parent
			local player = char and game:GetService("Players"):GetPlayerFromCharacter(char)
			if not player then
				return
			end
			local now = os.clock()
			if lastJack[player.UserId] and now - lastJack[player.UserId] < 90 then
				return
			end
			lastJack[player.UserId] = now
			PlayerData.AddCoins(player, 250)
		end)
		for k = 0, 11 do
			local ang = k * math.pi / 6
			addSkyPad(peak.X + math.cos(ang) * 16, peakY - 6, peak.Z + math.sin(ang) * 16, 3.0, peak.Ground)
		end
	end

	sky.Parent = workspace
	print("[PlotSystem] SkyGold pads " .. tostring(padCount))
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
	local dest = Vector3.new(bp.X, bp.Y + 5, bp.Z + PLOT_SIZE / 2 - 8)
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

local function addDressing(model: Model, height: number, def: any, variantId: string?, isShiny: boolean, host: BasePart?, skipPlate: boolean?)
	model:SetAttribute("BrainrotId", def.Id)
	if variantId then
		model:SetAttribute("Variant", variantId)
	end
	if isShiny then
		model:SetAttribute("Shiny", true)
	end
	local accentColor = BrainrotData.RARITY_COLORS[def.Rarity] or Color3.new(1, 1, 1)
	if isShiny then
		accentColor = Color3.fromRGB(255, 215, 0)
	end

	if not skipPlate then
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
	end

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

	-- Nameplates are drawn by the client (small, distance-faded).
	-- Rarity stays on this floor plate so the air above the plot stays readable.
end

local function findCustomModel(def: any, variantId: string?): Instance?
	local folder = ReplicatedStorage:FindFirstChild("BrainrotModels")
	if not (folder and folder:IsA("Folder")) then
		return nil
	end
	if variantId and variantId ~= "" then
		local variantModel = folder:FindFirstChild(def.Id .. "__" .. variantId)
		if variantModel then
			return variantModel
		end
	end
	local exact = folder:FindFirstChild(def.Id)
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

local function buildFromCustom(def: any, source: Instance, isShiny: boolean, variantId: string?, skipPlate: boolean?): Model?
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
	model:SetAttribute("BrainrotId", def.Id)
	if variantId then
		model:SetAttribute("Variant", variantId)
	end
	if isShiny then
		model:SetAttribute("Shiny", true)
	end

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
	model.PrimaryPart = host

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
		s = math.clamp(s, 0.02, 1)
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

	shrinkToPedestalSize(model)
	fitLyingFileMesh(model, MAX_DISPLAY_SIZE)
	uprightModel(model)
	addDressing(model, h, def, variantId, isShiny, host, skipPlate)
	return model
end

function PlotSystem.BuildDisplayModel(def: any, isShiny: boolean, variantId: string?, skipPlate: boolean?): Model
	local custom = findCustomModel(def, variantId)
	if custom then
		local fromCustom = buildFromCustom(def, custom, isShiny, variantId, skipPlate)
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

	model.PrimaryPart = body
	addDressing(model, spec.Size.Y, def, variantId, isShiny, body, skipPlate)
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
			if inst.Variant then
				display:SetAttribute("Variant", inst.Variant)
			end
			if inst.Shiny then
				display:SetAttribute("Shiny", true)
			end
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
	return ARENA_X, ARENA_Z
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
		rec.pModels[i] = spawnOne(f, cx - 8 * ARENA_SCALE, cz - 4 * ARENA_SCALE + (i - 1) * 4 * ARENA_SCALE, math.pi / 2, (i - 1) * 0.25)
	end
	for i, f in ipairs(eFighters) do
		rec.eModels[i] = spawnOne(f, cx + 8 * ARENA_SCALE, cz - 4 * ARENA_SCALE + (i - 1) * 4 * ARENA_SCALE, -math.pi / 2, 0.5 + (i - 1) * 0.25)
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
	if event.kind == "heal" or event.kind == "boost" then
		local atkTeam = if event.attackerSide == "player" then rec.pModels else rec.eModels
		local atk = atkTeam[event.attackerIdx]
		if atk and atk.model and atk.model.Parent then
			burst(rec.folder, atk.baseCF.Position + Vector3.new(0, 2, 0),
				if event.kind == "heal" then Color3.fromRGB(80, 220, 120) else Color3.fromRGB(255, 200, 80),
				18, 12, 0.7)
			if atk.hpBar and event.targetHp ~= nil then
				setHpBar(atk.hpBar, event.targetHp, atk.maxHp)
			end
			task.wait(0.45)
		end
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
