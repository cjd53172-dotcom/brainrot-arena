--!strict
--[[
	BlenderPropPlacer (ModuleScript -> ServerScriptService/Systems)

	Looks for ServerStorage.BlenderProps (preferred) or Workspace.BlenderProps,
	clones each named prop, scales it down, and seats it on terrain at the
	game's plaza / arena coordinates. Safe to call every server start.
]]

local ServerStorage = game:GetService("ServerStorage")

local BlenderPropPlacer = {}

local TARGETS: { [string]: number } = {
	Arena = 100,
	PlayerPlot = 56,
	GoldMine = 22,
	FishingDock = 28,
	VendorStall = 16,
	TrainerStall = 16,
	SignPost = 12,
	FishingSign = 12,
	Sword = 6,
	Mace = 7,
	Axe = 7,
	Skateboard = 5,
	MagicCarpet = 8,
	MiniPlane = 10,
}

local WORLD_DX, WORLD_DZ = 127, 98
local ARENA_X, ARENA_Z = WORLD_DX - 300, WORLD_DZ - 260
local PLAZA_Z, PLAZA_GAP, PLAZA_X0 = 28, 24, 68

local SPOTS: { [string]: { number } } = {
	Arena = { ARENA_X, ARENA_Z },
	VendorStall = { PLAZA_X0, PLAZA_Z },
	TrainerStall = { PLAZA_X0 + PLAZA_GAP * 2, PLAZA_Z },
	FishingDock = { 70, 20 },
	FishingSign = { 68, 8 },
	GoldMine = { WORLD_DX - 45, WORLD_DZ - 35 },
	SignPost = { PLAZA_X0 + PLAZA_GAP, PLAZA_Z + 20 },
	PlayerPlot = { WORLD_DX + 120, WORLD_DZ + 120 },
	Sword = { PLAZA_X0 - 14, PLAZA_Z + 12 },
	Mace = { PLAZA_X0 - 10, PLAZA_Z + 12 },
	Axe = { PLAZA_X0 - 6, PLAZA_Z + 12 },
	Skateboard = { PLAZA_X0 + 10, PLAZA_Z + 14 },
	MagicCarpet = { PLAZA_X0 + 16, PLAZA_Z + 14 },
	MiniPlane = { PLAZA_X0 + 22, PLAZA_Z + 14 },
}

local function anchorAll(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = true
		end
	end
	if not model.PrimaryPart then
		local part = model:FindFirstChildWhichIsA("BasePart", true)
		if part then
			model.PrimaryPart = part
		end
	end
end

local function fitToMax(model: Model, maxSize: number)
	anchorAll(model)
	local ok, size = pcall(function()
		local _, s = model:GetBoundingBox()
		return s
	end)
	if not ok or typeof(size) ~= "Vector3" then
		return
	end
	local longest = math.max(size.X, size.Y, size.Z)
	if longest > maxSize and longest > 0.01 then
		pcall(function()
			model:ScaleTo(model:GetScale() * (maxSize / longest))
		end)
	end
end

local function sitOnTerrain(model: Model, x: number, z: number, ignore: Instance)
	anchorAll(model)
	model:PivotTo(CFrame.new(x, 200, z))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { ignore }
	local hit = workspace:Raycast(Vector3.new(x, 800, z), Vector3.new(0, -2000, 0), params)
	local gy = if hit then hit.Position.Y else 0
	local boxCF, boxSize = model:GetBoundingBox()
	local bottomY = boxCF.Position.Y - boxSize.Y * 0.5
	model:TranslateBy(Vector3.new(0, gy - bottomY + 0.1, 0))
end

function BlenderPropPlacer.Setup()
	local templates = ServerStorage:FindFirstChild("BlenderProps")
	if not (templates and templates:IsA("Folder")) then
		local inWorld = workspace:FindFirstChild("BlenderProps")
		if inWorld and inWorld:IsA("Folder") then
			-- Move out of spawn so players aren't trapped; keep as templates.
			inWorld.Parent = ServerStorage
			templates = inWorld
			print("[BlenderPropPlacer] moved Workspace.BlenderProps → ServerStorage")
		else
			print("[BlenderPropPlacer] no BlenderProps folder — skip")
			return
		end
	end

	-- Hide originals deep underground in ServerStorage (already not rendered).
	local placedFolder = workspace:FindFirstChild("BlenderPropsPlaced")
	if placedFolder then
		placedFolder:Destroy()
	end
	placedFolder = Instance.new("Folder")
	placedFolder.Name = "BlenderPropsPlaced"
	placedFolder.Parent = workspace

	local count = 0
	for name, xz in pairs(SPOTS) do
		local src = templates:FindFirstChild(name)
		if src and src:IsA("Model") then
			local clone = src:Clone()
			clone.Name = name
			clone.Parent = placedFolder
			fitToMax(clone, TARGETS[name] or 20)
			sitOnTerrain(clone, xz[1], xz[2], placedFolder)
			count += 1
		end
	end
	print("[BlenderPropPlacer] placed " .. tostring(count) .. " props")
end

return BlenderPropPlacer
