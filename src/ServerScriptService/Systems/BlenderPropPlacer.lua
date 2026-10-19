--!strict
--[[
	BlenderPropPlacer — place ServerStorage.BlenderProps and hide legacy builds.
]]

local ServerStorage = game:GetService("ServerStorage")

local BlenderPropPlacer = {}

local TARGETS: { [string]: number } = {
	Arena = 90,
	PlayerPlot = 52,
	GoldMine = 20,
	FishingDock = 24,
	VendorStall = 14,
	TrainerStall = 14,
	SignPost = 8,
	FishingSign = 8,
	Sword = 5,
	Mace = 6,
	Axe = 6,
	Skateboard = 4,
	MagicCarpet = 6,
	MiniPlane = 8,
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
	GoldMine = { 227, 98 },
	SignPost = { PLAZA_X0 + PLAZA_GAP, PLAZA_Z + 18 },
	Sword = { PLAZA_X0 - 10, PLAZA_Z + 10 },
	Mace = { PLAZA_X0 - 7, PLAZA_Z + 10 },
	Axe = { PLAZA_X0 - 4, PLAZA_Z + 10 },
	Skateboard = { PLAZA_X0 + 8, PLAZA_Z + 10 },
	MagicCarpet = { PLAZA_X0 + 12, PLAZA_Z + 10 },
	MiniPlane = { PLAZA_X0 + 16, PLAZA_Z + 10 },
	PlayerPlot = { WORLD_DX + 160, WORLD_DZ + 160 },
}

local COLOR_RULES: { { string | Color3 | Enum.Material } } = {
	{ "Flame", Color3.fromRGB(255, 140, 40), Enum.Material.Neon },
	{ "Lantern", Color3.fromRGB(255, 186, 80), Enum.Material.Neon },
	{ "Gold", Color3.fromRGB(228, 184, 72), Enum.Material.Metal },
	{ "Banner", Color3.fromRGB(180, 40, 48), Enum.Material.Fabric },
	{ "Water", Color3.fromRGB(42, 120, 168), Enum.Material.Glass },
	{ "Steel", Color3.fromRGB(180, 186, 196), Enum.Material.Metal },
	{ "Metal", Color3.fromRGB(140, 144, 150), Enum.Material.Metal },
	{ "Blade", Color3.fromRGB(190, 196, 205), Enum.Material.Metal },
	{ "Rock", Color3.fromRGB(108, 102, 96), Enum.Material.Slate },
	{ "Stone", Color3.fromRGB(120, 114, 108), Enum.Material.Concrete },
	{ "Wall", Color3.fromRGB(150, 142, 132), Enum.Material.Marble },
	{ "Floor", Color3.fromRGB(196, 154, 96), Enum.Material.Sand },
	{ "Plank", Color3.fromRGB(158, 108, 58), Enum.Material.WoodPlanks },
	{ "Deck", Color3.fromRGB(158, 108, 58), Enum.Material.WoodPlanks },
	{ "Wood", Color3.fromRGB(110, 72, 40), Enum.Material.Wood },
	{ "Haft", Color3.fromRGB(110, 72, 40), Enum.Material.Wood },
	{ "Piling", Color3.fromRGB(70, 42, 24), Enum.Material.Wood },
	{ "Post", Color3.fromRGB(78, 50, 30), Enum.Material.Wood },
	{ "Sign", Color3.fromRGB(36, 24, 16), Enum.Material.Wood },
	{ "Rope", Color3.fromRGB(196, 170, 120), Enum.Material.Fabric },
	{ "Awning", Color3.fromRGB(200, 48, 48), Enum.Material.Fabric },
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
	model:TranslateBy(Vector3.new(0, gy - (boxCF.Position.Y - boxSize.Y * 0.5) + 0.1, 0))
end

local function paint(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d:IsA("MeshPart") then
				pcall(function()
					(d :: MeshPart).TextureID = ""
				end)
			end
			local sa = d:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				sa:Destroy()
			end
			for _, r in ipairs(COLOR_RULES) do
				if string.find(d.Name, r[1] :: string, 1, true) then
					d.Color = r[2] :: Color3
					d.Material = r[3] :: Enum.Material
					break
				end
			end
		end
	end
end

local function anyPart(model: Model): BasePart?
	return model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
end

local function hideModel(inst: Instance)
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide = false
			d.CanQuery = false
		end
	end
end

local function movePrompts(fromModel: Instance?, toModel: Model)
	if not fromModel then
		return
	end
	local dest = anyPart(toModel)
	if not dest then
		return
	end
	for _, d in ipairs(fromModel:GetDescendants()) do
		if d:IsA("ProximityPrompt") then
			d.Parent = dest
		end
	end
	for _, child in ipairs(fromModel:GetChildren()) do
		if child:IsA("Model") and (child.Name == "Shopkeeper" or child.Name == "Trainer") then
			child.Parent = toModel
			child:PivotTo(toModel:GetPivot() * CFrame.new(0, 3, -1))
		end
	end
end

function BlenderPropPlacer.Setup()
	-- Off by default: procedural Roblox props look better than these FBX imports.
	-- Set Workspace attribute UseBlenderProps = true to opt in later.
	if workspace:GetAttribute("UseBlenderProps") ~= true then
		print("[BlenderPropPlacer] skipped (set Workspace.UseBlenderProps = true to enable)")
		return
	end

	local templates = ServerStorage:FindFirstChild("BlenderProps")
	if not (templates and templates:IsA("Folder")) then
		local inWorld = workspace:FindFirstChild("BlenderProps")
		if inWorld and inWorld:IsA("Folder") then
			inWorld.Parent = ServerStorage
			templates = inWorld
		else
			print("[BlenderPropPlacer] no BlenderProps — skip")
			return
		end
	end

	local placedFolder = workspace:FindFirstChild("BlenderPropsPlaced")
	if placedFolder then
		placedFolder:Destroy()
	end
	placedFolder = Instance.new("Folder")
	placedFolder.Name = "BlenderPropsPlaced"
	placedFolder.Parent = workspace

	local models: { [string]: Model } = {}
	for name, xz in pairs(SPOTS) do
		local src = (templates :: Folder):FindFirstChild(name)
		if src and src:IsA("Model") then
			local clone = src:Clone()
			clone.Name = name
			clone.Parent = placedFolder
			fitToMax(clone, TARGETS[name] or 16)
			sitOnTerrain(clone, xz[1], xz[2], placedFolder)
			paint(clone)
			models[name] = clone
		end
	end

	if models.VendorStall then
		local shop = workspace:FindFirstChild("RobuxShop", true)
		movePrompts(shop, models.VendorStall)
		if shop then
			hideModel(shop)
		end
	end
	if models.TrainerStall then
		local trainer = workspace:FindFirstChild("StatTrainerStall", true)
		movePrompts(trainer, models.TrainerStall)
		if trainer then
			hideModel(trainer)
		end
	end
	if models.GoldMine then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.ActionText == "Mine Gold" then
				local host = d:FindFirstAncestorOfClass("Model")
				local dest = anyPart(models.GoldMine)
				if dest then
					d.Parent = dest
				end
				if host and host ~= models.GoldMine then
					hideModel(host)
				end
				break
			end
		end
	end
	if models.FishingDock then
		for _, d in ipairs(workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and (d.Name == "FishPrompt" or d.ActionText == "Cast Line") then
				local host = d:FindFirstAncestorOfClass("Model")
				local dest = anyPart(models.FishingDock)
				if dest then
					d.Parent = dest
				end
				if host and host.Name == "FishingSpot" then
					hideModel(host)
				end
			end
		end
	end
	if models.Arena then
		local colo = workspace:FindFirstChild("Colosseum", true)
		if colo then
			hideModel(colo)
		end
	end

	print("[BlenderPropPlacer] placed + replaced legacy props")
end

return BlenderPropPlacer
